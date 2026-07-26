import Foundation
import CloudKit
import SwiftData
import Combine
import os

/// Core CloudKit sync engine that mirrors local SwiftData to a private CloudKit database.
/// The local store is always the source of truth; CloudKit acts as a mirror.
@MainActor
final class CloudSyncService: ObservableObject {

    // MARK: - Properties

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.tianshilei.fuelio",
        category: "CloudSync"
    )

    let stateManager: SyncStateManager

    /// CloudKit container — created lazily so the app never touches CloudKit
    /// until the user actually tries to enable iCloud sync.
    /// Uses the default container configured in the app's entitlements.
    private lazy var container: CKContainer = {
        CKContainer.default()
    }()

    private lazy var privateDatabase: CKDatabase = {
        container.privateCloudDatabase
    }()

    private lazy var zoneID: CKRecordZone.ID = {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }()

    private var saveObserver: AnyCancellable?
    private var stateForwardingObserver: AnyCancellable?
    private var modelContainer: ModelContainer?
    private let operationCoordinator = SyncOperationCoordinator()

    /// Counted scope prevents one nested/overlapping operation from clearing
    /// suppression while another remote application is still active.
    private var remoteApplicationDepth = 0

    /// Suppresses automatic local-save pushes while a vetted bulk write is in progress.
    private var localPushSuspensionCount = 0

    /// Snapshot of local UUIDs from the last successful push, used to detect
    /// local deletions without fetching all cloud records every time.
    private var lastKnownLocalUUIDs: Set<String> = []
    private var lastPushDate: Date = .distantPast

    // MARK: - Constants

    private typealias RecordType = CloudRecordCodec.RecordType

    /// Compatibility namespaces retained for the existing test and call seams.
    typealias CloudFieldKey = CloudRecordCodec.CloudFieldKey
    typealias ConflictWinner = SyncConflictResolver.Winner
    typealias CloudReplacementError = CloudSnapshotValidator.ValidationError
    typealias RemoteApplyResult = CloudReconciliationService.RemoteApplyResult

    private static let zoneName = "FuelioZone"
    private static let subscriptionID = "FuelioZoneChanges"

    /// CloudKit has a 400-record limit per operation; we use a smaller batch for reliability.
    private static let batchSize = 200
    /// Maximum retry attempts for a failed batch save.
    private static let maxRetries = 3
    /// Delay between retry attempts (in nanoseconds per attempt, multiplied by attempt number).
    private static let retryBaseDelay: UInt64 = 2_000_000_000  // 2 seconds
    /// Delay between consecutive batch operations to avoid rate limiting.
    private static let interBatchDelay: UInt64 = 500_000_000  // 0.5 seconds
    /// Debounce interval for local save observations (seconds).
    private static let saveDebounceInterval: TimeInterval = 1

    private var recordCodec: CloudRecordCodec {
        CloudRecordCodec(zoneID: zoneID)
    }

    private var reconciliationService: CloudReconciliationService {
        CloudReconciliationService(codec: recordCodec)
    }

    // MARK: - Initialization

    init(stateManager: SyncStateManager = SyncStateManager()) {
        self.stateManager = stateManager

        // Forward stateManager's change notifications so that views observing
        // CloudSyncService (via @EnvironmentObject) also re-render when
        // syncStatus, iCloudSyncEnabled, etc. change.
        stateForwardingObserver = stateManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    // MARK: - iCloud Availability

    /// Check if the user is signed in to iCloud
    func checkiCloudAvailability() async -> Bool {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                return true
            default:
                await MainActor.run {
                    stateManager.syncStatus = .unavailable
                }
                return false
            }
        } catch {
            await MainActor.run {
                stateManager.syncStatus = .error(String(localized: "Failed to check iCloud status"))
            }
            return false
        }
    }

    // MARK: - Zone Management

    /// Ensure the custom record zone exists
    private func ensureZoneExists() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        let _ = try await privateDatabase.modifyRecordZones(saving: [zone], deleting: [])
    }

    // MARK: - Initial Sync Check

    /// Check if the cloud has any data in FuelioZone.
    /// Uses recordZoneChanges (change token based) instead of CKQuery to avoid
    /// issues with non-existent record types and non-queryable fields on first use.
    func checkCloudHasData() async throws -> Bool {
        try await operationCoordinator.runExclusive {
            do {
                return try await performCheckCloudHasData()
            } catch {
                stateManager.syncStatus = .error(String(localized: "Sync failed"))
                throw error
            }
        }
    }

    private func performCheckCloudHasData() async throws -> Bool {
        try await ensureZoneExists()

        // Read the complete zone instead of treating an empty first page as an
        // empty cloud. Errors intentionally propagate: callers must distinguish
        // "empty" from "unknown because CloudKit failed" before choosing the
        // destructive initial-sync strategy.
        let (vehicles, fuelingRecords) = try await fetchAllCloudRecords()
        return !vehicles.isEmpty || !fuelingRecords.isEmpty
    }

    // MARK: - Upload All Local Data

    /// Upload all local vehicles and fueling records to CloudKit
    func uploadAllLocalData(from context: ModelContext) async throws {
        try await operationCoordinator.runExclusive {
            do {
                try await performUploadAllLocalData(from: context)
            } catch {
                stateManager.syncStatus = .error(String(localized: "Sync failed"))
                throw error
            }
        }
    }

    private func performUploadAllLocalData(from context: ModelContext) async throws {
        stateManager.syncStatus = .syncing

        try await ensureZoneExists()

        // Fetch all local vehicles
        let vehicleDescriptor = FetchDescriptor<Vehicle>()
        let vehicles = try context.fetch(vehicleDescriptor)

        var recordsToSave: [CKRecord] = []

        for vehicle in vehicles {
            let vehicleRecord = vehicleToCKRecord(vehicle)
            recordsToSave.append(vehicleRecord)

            // Add fueling records for this vehicle
            for fuelingRecord in vehicle.fuelingRecords ?? [] {
                let ckRecord = fuelingRecordToCKRecord(fuelingRecord, vehicleRecordID: vehicleRecord.recordID)
                recordsToSave.append(ckRecord)
            }
        }

        // Batch save in chunks (CloudKit has a 400 record limit per operation)
        try await batchSave(records: recordsToSave)

        stateManager.syncStatus = .synced
    }

    // MARK: - Download All Cloud Data

    /// Download all cloud data and replace local data.
    ///
    /// The complete cloud snapshot is decoded and validated before touching the
    /// local context. The replacement is then persisted by one `save()`, which
    /// SwiftData commits as one store transaction. If that save fails, rollback
    /// restores the context to its last successfully saved local state.
    func downloadAllCloudData(to context: ModelContext) async throws {
        try await operationCoordinator.runExclusive {
            do {
                try await performDownloadAllCloudData(to: context)
            } catch {
                stateManager.syncStatus = .error(String(localized: "Sync failed"))
                throw error
            }
        }
    }

    private func performDownloadAllCloudData(to context: ModelContext) async throws {
        stateManager.syncStatus = .syncing
        remoteApplicationDepth += 1
        defer { remoteApplicationDepth -= 1 }

        // Fetch cloud data before deleting local data. If iCloud fails here, the
        // local store remains untouched.
        let (vehicleCKRecords, fuelingCKRecords) = try await fetchAllCloudRecords()

        try replaceLocalData(
            vehicleCKRecords: vehicleCKRecords,
            fuelingCKRecords: fuelingCKRecords,
            context: context
        )

        // Rebuild all caches
        StatisticsCacheService.rebuildCacheForAllVehicles(in: context, force: true)

        stateManager.syncStatus = .synced
    }

    /// Network-free replacement seam used by `downloadAllCloudData` and tests.
    ///
    /// Validation happens before the first context mutation. Any pending local
    /// edits are saved first so rollback cannot discard unrelated user changes.
    func replaceLocalData(
        vehicleCKRecords: [CKRecord],
        fuelingCKRecords: [CKRecord],
        context: ModelContext
    ) throws {
        let validatedSnapshot = try CloudSnapshotValidator().validate(
            vehicleRecords: vehicleCKRecords,
            fuelingRecordRecords: fuelingCKRecords
        )
        let vehicleSnapshots = validatedSnapshot.vehicles
        let fuelingSnapshots = validatedSnapshot.fuelingRecords

        // Establish a clean rollback boundary before beginning the replacement.
        if context.hasChanges {
            try context.save()
        }

        do {
            let localVehicles = try context.fetch(FetchDescriptor<Vehicle>())
            for vehicle in localVehicles {
                context.delete(vehicle)
            }

            var vehiclesByID: [UUID: Vehicle] = [:]
            vehiclesByID.reserveCapacity(vehicleSnapshots.count)

            for snapshot in vehicleSnapshots {
                let vehicle = Vehicle(
                    id: snapshot.id,
                    name: snapshot.name,
                    make: snapshot.make,
                    model: snapshot.model,
                    year: snapshot.year,
                    createdAt: snapshot.createdAt,
                    unitSystem: snapshot.unitSystem
                )
                vehicle.modifiedAt = snapshot.modifiedAt
                context.insert(vehicle)
                vehiclesByID[snapshot.id] = vehicle
            }

            for snapshot in fuelingSnapshots {
                guard let vehicle = vehiclesByID[snapshot.vehicleID] else {
                    throw CloudReplacementError.missingVehicle(
                        recordID: snapshot.id,
                        vehicleID: snapshot.vehicleID
                    )
                }

                let record = FuelingRecord(
                    id: snapshot.id,
                    date: snapshot.date,
                    odometer: snapshot.odometer,
                    pricePerFuelUnit: snapshot.pricePerFuelUnit,
                    fuelAmount: snapshot.fuelAmount,
                    totalCost: snapshot.totalCost,
                    fillUpType: snapshot.fillUpType,
                    notes: snapshot.notes,
                    createdAt: snapshot.createdAt,
                    vehicle: vehicle
                )
                record.modifiedAt = snapshot.modifiedAt
                context.insert(record)
            }

            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: - Merge Cloud and Local

    /// Merge cloud and local data: match by UUID, keep newer for matches, insert unique from both sides
    func mergeCloudAndLocal(context: ModelContext) async throws {
        try await operationCoordinator.runExclusive {
            do {
                try await performMergeCloudAndLocal(context: context)
            } catch {
                stateManager.syncStatus = .error(String(localized: "Sync failed"))
                throw error
            }
        }
    }

    private func performMergeCloudAndLocal(context: ModelContext) async throws {
        stateManager.syncStatus = .syncing
        remoteApplicationDepth += 1
        defer { remoteApplicationDepth -= 1 }

        // Fetch all cloud records using change token (avoids queryable field requirements)
        let (vehicleCKRecords, fuelingCKRecords) = try await fetchAllCloudRecords()

        // Reconcile in memory: pull cloud-newer values down, insert cloud-only
        // records, and collect the records that must be pushed back up.
        let recordsToUpload = try reconcileMerge(
            vehicleCKRecords: vehicleCKRecords,
            fuelingCKRecords: fuelingCKRecords,
            context: context
        )

        // Batch upload
        if !recordsToUpload.isEmpty {
            try await batchSave(records: recordsToUpload)
        }

        try context.save()

        // Rebuild all caches
        StatisticsCacheService.rebuildCacheForAllVehicles(in: context, force: true)

        stateManager.syncStatus = .synced
    }

    /// Pure, network-free reconciliation used by ``mergeCloudAndLocal(context:)``.
    ///
    /// Mutates `context` in place (updates local from cloud where the cloud copy
    /// is newer, inserts cloud-only records) and returns the CKRecords that must
    /// be uploaded to the cloud. Records are uploaded when they are local-only
    /// **or** when they exist on both sides but the local copy is newer — the
    /// latter case is what previously left other devices stuck with stale data.
    ///
    /// Extracted so the conflict/upload logic can be unit-tested without CloudKit.
    func reconcileMerge(
        vehicleCKRecords: [CKRecord],
        fuelingCKRecords: [CKRecord],
        context: ModelContext
    ) throws -> [CKRecord] {
        try reconciliationService.reconcileMerge(
            vehicleCKRecords: vehicleCKRecords,
            fuelingCKRecords: fuelingCKRecords,
            context: context
        )
    }

    // MARK: - Delete All Cloud Data

    /// Atomically reserves the sync pipeline for the complete destructive
    /// delete-and-upload sequence so no automatic pull or push can observe the
    /// temporary empty cloud zone.
    func replaceCloudDataWithLocal(from context: ModelContext) async throws {
        try await operationCoordinator.runExclusive {
            do {
                try await performDeleteAllCloudData()
                try await performUploadAllLocalData(from: context)
            } catch {
                stateManager.syncStatus = .error(String(localized: "Sync failed"))
                throw error
            }
        }
    }

    private func performDeleteAllCloudData() async throws {
        stateManager.syncStatus = .syncing

        // Deleting the zone deletes all records in it
        let _ = try await privateDatabase.modifyRecordZones(saving: [], deleting: [zoneID])

        // Recreate the zone for future use
        try await ensureZoneExists()

        // Reset the change token
        stateManager.serverChangeToken = nil
    }

    // MARK: - Cloud Record Counts

    /// Fetch the number of vehicles and fueling records currently in CloudKit.
    func fetchCloudRecordCounts() async -> (vehicles: Int, fuelingRecords: Int) {
        await operationCoordinator.runExclusive {
            do {
                let (vehicles, fuelingRecords) = try await fetchAllCloudRecords()
                return (vehicles.count, fuelingRecords.count)
            } catch {
                Self.logger.error("Failed to fetch cloud record counts: \(error)")
                return (0, 0)
            }
        }
    }

    // MARK: - Fetch All Cloud Records Helper

    /// Fetch all records from the custom zone using recordZoneChanges (change-token based).
    /// This avoids CKQuery which requires fields to be marked queryable in the CloudKit dashboard.
    /// Returns separate arrays for Vehicle and FuelingRecord CKRecords.
    private func fetchAllCloudRecords() async throws -> (vehicles: [CKRecord], fuelingRecords: [CKRecord]) {
        // Use dictionaries to deduplicate by CKRecord.ID.
        // recordZoneChanges(since: nil) returns the full change history,
        // so the same record can appear multiple times if it was re-uploaded.
        // Keeping the latest version (last write wins).
        var vehicleRecords: [CKRecord.ID: CKRecord] = [:]
        var fuelingRecords: [CKRecord.ID: CKRecord] = [:]
        var changeToken: CKServerChangeToken? = nil
        var moreComing = true

        while moreComing {
            let results = try await privateDatabase.recordZoneChanges(
                inZoneWith: zoneID,
                since: changeToken
            )

            for (recordID, result) in results.modificationResultsByID {
                switch result {
                case .success(let modification):
                    let record = modification.record
                    switch record.recordType {
                    case RecordType.vehicle:
                        vehicleRecords[recordID] = record
                    case RecordType.fuelingRecord:
                        fuelingRecords[recordID] = record
                    default:
                        break
                    }
                case .failure(let error):
                    // A successful page can still contain failed individual
                    // records. Returning the rest would create a partial
                    // snapshot and could make replacement delete valid local
                    // data that merely failed to download.
                    Self.logger.error("Full-zone fetch failed for \(recordID.recordName): \(error.localizedDescription)")
                    throw error
                }
            }

            // Track deletions so we don't count deleted records
            for deletion in results.deletions {
                let recordID = deletion.recordID
                vehicleRecords.removeValue(forKey: recordID)
                fuelingRecords.removeValue(forKey: recordID)
            }

            changeToken = results.changeToken
            moreComing = results.moreComing
        }

        return (Array(vehicleRecords.values), Array(fuelingRecords.values))
    }

    // MARK: - Incremental Pull

    /// Pull remote changes using server change tokens for efficient delta sync
    func pullRemoteChanges(to context: ModelContext) async {
        await operationCoordinator.runCoalesced(key: .pull) {
            await self.performPullRemoteChanges(to: context)
        }
    }

    private func performPullRemoteChanges(to context: ModelContext) async {
        guard stateManager.iCloudSyncEnabled && stateManager.initialSyncCompleted else { return }

        remoteApplicationDepth += 1
        defer { remoteApplicationDepth -= 1 }

        stateManager.syncStatus = .syncing

        do {
            var changedRecords: [CKRecord] = []
            var deletedRecordIDs: [CKRecord.ID] = []
            var changeToken = stateManager.serverChangeToken
            var moreComing = true
            var hadFetchFailure = false

            while moreComing {
                let results = try await privateDatabase.recordZoneChanges(
                    inZoneWith: zoneID,
                    since: changeToken
                )

                for (recordID, result) in results.modificationResultsByID {
                    switch result {
                    case .success(let modification):
                        changedRecords.append(modification.record)
                    case .failure(let error):
                        // We did not receive this record, so the change window
                        // is incomplete. Advancing the token would skip it
                        // permanently (and orphan any child whose parent failed
                        // here). Remember the failure and hold the token below.
                        hadFetchFailure = true
                        Self.logger.error("Change fetch failed for \(recordID.recordName): \(error.localizedDescription)")
                    }
                }

                for deletion in results.deletions {
                    deletedRecordIDs.append(deletion.recordID)
                }

                changeToken = results.changeToken
                moreComing = results.moreComing
            }

            var unresolvedChildIDs: [UUID] = []
            if !changedRecords.isEmpty || !deletedRecordIDs.isEmpty {
                let applyResult = try applyRemoteChanges(
                    changedRecords: changedRecords,
                    deletedRecordIDs: deletedRecordIDs,
                    context: context
                )

                // Push local copies that won conflict resolution so the stale
                // cloud values (and other devices) converge, rather than waiting
                // for the next unrelated local save to trigger a push.
                if !applyResult.recordsToUpload.isEmpty {
                    try await batchSave(records: applyResult.recordsToUpload)
                }

                unresolvedChildIDs = applyResult.unresolvedChildIDs
                if !unresolvedChildIDs.isEmpty {
                    Self.logger.error("Holding change token: \(unresolvedChildIDs.count) fueling record(s) have an unresolved parent vehicle and will be retried")
                }
            }

            // Advance the change token only when the whole window applied safely
            // (no fetch failures and no unresolved children). See `commitPullOutcome`.
            commitPullOutcome(
                fetchedToken: changeToken,
                hadFetchFailure: hadFetchFailure,
                unresolvedChildIDs: unresolvedChildIDs
            )
        } catch {
            Self.logger.error("Failed to pull remote changes: \(error)")
            stateManager.syncStatus = .error(String(localized: "Pull failed"))
        }
    }

    /// Commit the result of a pull by deciding whether the server change token
    /// may advance.
    ///
    /// The token advances only when the entire change window was applied
    /// safely: no per-record fetch failure **and** no fueling record left
    /// unresolved because its parent vehicle was missing. In either of those
    /// cases the token is held so the same window is re-delivered on the next
    /// pull (re-application is idempotent) and the record is picked up once its
    /// parent arrives — advancing would move the token past a record that was
    /// never stored locally, skipping it forever, which this app's
    /// data-integrity guarantees forbid.
    ///
    /// Extracted from ``pullRemoteChanges(to:)`` so the token-advance decision
    /// can be unit-tested without CloudKit.
    ///
    /// - Returns: `true` if the token advanced, `false` if it was held.
    @discardableResult
    func commitPullOutcome(
        fetchedToken: CKServerChangeToken?,
        hadFetchFailure: Bool,
        unresolvedChildIDs: [UUID]
    ) -> Bool {
        guard !hadFetchFailure && unresolvedChildIDs.isEmpty else {
            stateManager.syncStatus = .error(String(localized: "Pull incomplete — will retry"))
            return false
        }
        stateManager.serverChangeToken = fetchedToken
        stateManager.syncStatus = .synced
        return true
    }

    /// Apply fetched remote changes to the local store.
    ///
    /// Vehicles are applied before fueling records: CloudKit does not guarantee
    /// ordering within a change set, so a fueling record and its brand-new parent
    /// vehicle may arrive in either order. Processing the record first used to
    /// drop it (its owner wasn't inserted yet) while the change token still
    /// advanced, losing the record permanently. A two-pass apply removes that
    /// dependency on arrival order.
    ///
    /// Existing local objects are overwritten only when the incoming cloud copy
    /// is strictly newer (last-writer-wins). When the local copy is newer it is
    /// kept *and* returned in ``RemoteApplyResult/recordsToUpload`` so the caller
    /// can push it back to the cloud, keeping devices convergent.
    ///
    /// A fueling record whose parent vehicle cannot be resolved is left
    /// un-applied and reported in ``RemoteApplyResult/unresolvedChildIDs`` rather
    /// than silently dropped.
    @discardableResult
    func applyRemoteChanges(changedRecords: [CKRecord], deletedRecordIDs: [CKRecord.ID], context: ModelContext) throws -> RemoteApplyResult {
        try reconciliationService.applyRemoteChanges(
            changedRecords: changedRecords,
            deletedRecordIDs: deletedRecordIDs,
            context: context
        )
    }

    // MARK: - Subscriptions

    /// Subscribe to remote changes via CKDatabaseSubscription
    func subscribeToRemoteChanges() async {
        // Check if already subscribed
        do {
            let _ = try await privateDatabase.subscription(for: Self.subscriptionID)
            // Already subscribed
            return
        } catch {
            // Not subscribed yet, proceed
        }

        let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // Silent push
        subscription.notificationInfo = notificationInfo

        do {
            let _ = try await privateDatabase.modifySubscriptions(saving: [subscription], deleting: [])
        } catch {
            Self.logger.error("Failed to create subscription: \(error)")
        }
    }

    // MARK: - Monitoring Local Changes

    /// Start monitoring local saves to auto-push changes
    func startMonitoring(container: ModelContainer) {
        self.modelContainer = container

        initializeKnownUUIDs(container: container)

        // Observe managed object context saves
        saveObserver = NotificationCenter.default.publisher(
            for: Notification.Name.NSManagedObjectContextDidSave
        )
        .map { [weak self] notification in
            (notification, self?.shouldSuppressAutomaticPush ?? false)
        }
        .debounce(for: .seconds(Self.saveDebounceInterval), scheduler: RunLoop.main)
        .sink { [weak self] output in
            let (_, wasSuppressedWhenSaved) = output
            guard let self = self,
                  Self.shouldScheduleAutomaticPush(
                      wasSuppressedWhenSaved: wasSuppressedWhenSaved,
                      isCurrentlySuppressed: self.shouldSuppressAutomaticPush
                  ) else { return }

            Task(priority: .utility) { @MainActor [weak self] in
                guard let self = self else { return }
                await self.requestLocalPush(container: container)
            }
        }
    }

    private var shouldSuppressAutomaticPush: Bool {
        remoteApplicationDepth > 0 || localPushSuspensionCount > 0
    }

    /// The save-time value is captured before debounce. This keeps a save made
    /// while applying remote records suppressed even though the pull has
    /// released its scope by the time the debounced observer runs.
    nonisolated static func shouldScheduleAutomaticPush(
        wasSuppressedWhenSaved: Bool,
        isCurrentlySuppressed: Bool
    ) -> Bool {
        !wasSuppressedWhenSaved && !isCurrentlySuppressed
    }

    /// Run a local bulk write without allowing intermediate saves to auto-push.
    func withLocalPushesSuspended<T>(_ operation: () throws -> T) rethrows -> T {
        localPushSuspensionCount += 1
        defer { localPushSuspensionCount -= 1 }
        return try operation()
    }

    /// Run an async local bulk write without allowing intermediate saves to auto-push.
    func withLocalPushesSuspended<T>(_ operation: () async throws -> T) async rethrows -> T {
        localPushSuspensionCount += 1
        defer { localPushSuspensionCount -= 1 }
        return try await operation()
    }

    /// Explicitly push local changes after a bulk write has completed successfully.
    func pushPendingLocalChanges() async {
        guard let modelContainer else { return }
        await requestLocalPush(container: modelContainer)
    }

    /// Populate lastKnownLocalUUIDs from the current database so the first push
    /// can detect deletions that happened while the app was closed.
    private func initializeKnownUUIDs(container: ModelContainer) {
        do {
            let context = container.mainContext
            let vehicles = try context.fetch(FetchDescriptor<Vehicle>())
            let records = try context.fetch(FetchDescriptor<FuelingRecord>())
            var uuids = Set<String>()
            for v in vehicles { uuids.insert(v.id.uuidString) }
            for r in records { uuids.insert(r.id.uuidString) }
            lastKnownLocalUUIDs = uuids
        } catch {
            Self.logger.error("Failed to initialize known UUIDs: \(error)")
        }
    }

    /// Stop monitoring local saves
    func stopMonitoring() {
        saveObserver?.cancel()
        saveObserver = nil
        modelContainer = nil
    }

    /// Push local changes to CloudKit incrementally.
    /// Only converts and uploads records whose `modifiedAt` is newer than the
    /// last successful push. Still walks the full UUID set to detect deletions.
    private func requestLocalPush(container: ModelContainer) async {
        await operationCoordinator.runCoalesced(key: .push) {
            await self.performPushLocalChangesToCloud(container: container)
        }
    }

    private func performPushLocalChangesToCloud(container: ModelContainer) async {
        guard stateManager.iCloudSyncEnabled && stateManager.initialSyncCompleted else { return }
        guard !shouldSuppressAutomaticPush else { return }

        do {
            stateManager.syncStatus = .syncing

            try await ensureZoneExists()

            let context = container.mainContext
            // Advance only to the time this local snapshot begins. A save that
            // occurs while CloudKit is uploading will have a later modifiedAt
            // and is therefore picked up by the coalesced trailing push.
            let snapshotDate = Date()
            let vehicleDescriptor = FetchDescriptor<Vehicle>()
            let localVehicles = try context.fetch(vehicleDescriptor)

            let cutoff = lastPushDate
            var currentUUIDs = Set<String>()
            var recordsToSave: [CKRecord] = []

            for vehicle in localVehicles {
                currentUUIDs.insert(vehicle.id.uuidString)

                let vehicleModified = vehicle.modifiedAt ?? vehicle.createdAt
                if vehicleModified > cutoff {
                    recordsToSave.append(vehicleToCKRecord(vehicle))
                }

                let vehicleRecordID = CKRecord.ID(recordName: vehicle.id.uuidString, zoneID: zoneID)
                for fuelingRecord in vehicle.fuelingRecords ?? [] {
                    currentUUIDs.insert(fuelingRecord.id.uuidString)
                    let recordModified = fuelingRecord.modifiedAt ?? fuelingRecord.createdAt
                    if recordModified > cutoff {
                        recordsToSave.append(fuelingRecordToCKRecord(fuelingRecord, vehicleRecordID: vehicleRecordID))
                    }
                }
            }

            // Detect deletions by diffing against last-known UUIDs
            let deletedUUIDs = lastKnownLocalUUIDs.subtracting(currentUUIDs)
            var idsToDelete: [CKRecord.ID] = []
            for uuid in deletedUUIDs {
                idsToDelete.append(CKRecord.ID(recordName: uuid, zoneID: zoneID))
            }

            if !recordsToSave.isEmpty {
                try await batchSave(records: recordsToSave)
            }

            if !idsToDelete.isEmpty {
                Self.logger.info("Deleting \(idsToDelete.count) stale cloud record(s)")
                try await batchDelete(recordIDs: idsToDelete)
            }

            lastKnownLocalUUIDs = currentUUIDs
            lastPushDate = snapshotDate
            stateManager.syncStatus = .synced
        } catch {
            Self.logger.error("Failed to push local changes to cloud: \(error)")
            stateManager.syncStatus = .error(String(localized: "Sync failed"))
        }
    }

    // MARK: - Conflict Resolution

    /// Decide which copy of a record is newer using `modifiedAt` with a
    /// `createdAt` fallback. Retained as a compatibility seam for tests.
    nonisolated static func resolveConflict(
        cloudModifiedAt: Date?,
        cloudCreatedAt: Date?,
        localModifiedAt: Date?,
        localCreatedAt: Date?
    ) -> ConflictWinner {
        SyncConflictResolver.resolve(
            cloudModifiedAt: cloudModifiedAt,
            cloudCreatedAt: cloudCreatedAt,
            localModifiedAt: localModifiedAt,
            localCreatedAt: localCreatedAt
        )
    }

    // MARK: - CKRecord Mapping

    /// Compatibility forwarding seam for existing tests and callers.
    func vehicleToCKRecord(_ vehicle: Vehicle) -> CKRecord {
        recordCodec.vehicleToCKRecord(vehicle)
    }

    /// Compatibility forwarding seam for existing tests and callers.
    func fuelingRecordToCKRecord(_ fuelingRecord: FuelingRecord, vehicleRecordID: CKRecord.ID) -> CKRecord {
        recordCodec.fuelingRecordToCKRecord(
            fuelingRecord,
            vehicleRecordID: vehicleRecordID
        )
    }

    // MARK: - Batch Operations

    /// Save records in batches with retry logic.
    private func batchSave(records: [CKRecord]) async throws {
        var offset = 0

        while offset < records.count {
            let end = min(offset + Self.batchSize, records.count)
            let batch = Array(records[offset..<end])

            var lastError: Error?
            var succeeded = false

            for attempt in 1...Self.maxRetries {
                do {
                    let (saveResults, _) = try await privateDatabase.modifyRecords(
                        saving: batch, deleting: [], savePolicy: .changedKeys
                    )

                    // Check per-record results for failures
                    var failedRecordIDs: [CKRecord.ID] = []
                    for (recordID, result) in saveResults {
                        if case .failure(let error) = result {
                            failedRecordIDs.append(recordID)
                            lastError = error
                            Self.logger.warning("Failed to save record \(recordID): \(error)")
                        }
                    }

                    if failedRecordIDs.isEmpty {
                        succeeded = true
                        break
                    } else {
                        Self.logger.warning("Batch attempt \(attempt): \(failedRecordIDs.count)/\(batch.count) records failed")
                        if attempt < Self.maxRetries {
                            try await Task.sleep(nanoseconds: UInt64(attempt) * Self.retryBaseDelay)
                        }
                    }
                } catch {
                    lastError = error
                    Self.logger.error("Batch save attempt \(attempt) threw error: \(error)")
                    if attempt < Self.maxRetries {
                        try await Task.sleep(nanoseconds: UInt64(attempt) * Self.retryBaseDelay)
                    }
                }
            }

            if !succeeded, let error = lastError {
                throw error
            }

            offset = end

            if offset < records.count {
                try await Task.sleep(nanoseconds: Self.interBatchDelay)
            }
        }
    }

    /// Delete CKRecord IDs in batches with retry logic.
    private func batchDelete(recordIDs: [CKRecord.ID]) async throws {
        var offset = 0

        while offset < recordIDs.count {
            let end = min(offset + Self.batchSize, recordIDs.count)
            let batch = Array(recordIDs[offset..<end])

            var lastError: Error?
            var succeeded = false

            for attempt in 1...Self.maxRetries {
                do {
                    let (_, deleteResults) = try await privateDatabase.modifyRecords(
                        saving: [], deleting: batch, savePolicy: .changedKeys
                    )

                    var failedIDs: [CKRecord.ID] = []
                    for (recordID, result) in deleteResults {
                        if case .failure(let error) = result {
                            failedIDs.append(recordID)
                            lastError = error
                            Self.logger.warning("Failed to delete record \(recordID): \(error)")
                        }
                    }

                    if failedIDs.isEmpty {
                        succeeded = true
                        break
                    } else {
                        Self.logger.warning("Delete batch attempt \(attempt): \(failedIDs.count)/\(batch.count) records failed")
                        if attempt < Self.maxRetries {
                            try await Task.sleep(nanoseconds: UInt64(attempt) * Self.retryBaseDelay)
                        }
                    }
                } catch {
                    lastError = error
                    Self.logger.error("Batch delete attempt \(attempt) threw error: \(error)")
                    if attempt < Self.maxRetries {
                        try await Task.sleep(nanoseconds: UInt64(attempt) * Self.retryBaseDelay)
                    }
                }
            }

            if !succeeded, let error = lastError {
                throw error
            }

            offset = end

            if offset < recordIDs.count {
                try await Task.sleep(nanoseconds: Self.interBatchDelay)
            }
        }
    }
}
