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

    /// Flag to prevent re-entrant push when we're applying remote changes locally
    private var isApplyingRemoteChanges = false

    /// Suppresses automatic local-save pushes while a vetted bulk write is in progress.
    private var localPushSuspensionCount = 0

    /// Snapshot of local UUIDs from the last successful push, used to detect
    /// local deletions without fetching all cloud records every time.
    private var lastKnownLocalUUIDs: Set<String> = []
    private var lastPushDate: Date = .distantPast

    // MARK: - Constants

    private enum RecordType {
        static let vehicle = "Vehicle"
        static let fuelingRecord = "FuelingRecord"
    }

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
    func checkCloudHasData() async -> Bool {
        do {
            try await ensureZoneExists()

            // Fetch all changes since the beginning (nil token) — if any records
            // come back, the cloud has data.
            let results = try await privateDatabase.recordZoneChanges(
                inZoneWith: zoneID,
                since: nil
            )

            return !results.modificationResultsByID.isEmpty
        } catch {
            Self.logger.error("Error checking cloud data: \(error)")
            return false
        }
    }

    // MARK: - Upload All Local Data

    /// Upload all local vehicles and fueling records to CloudKit
    func uploadAllLocalData(from context: ModelContext) async throws {
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

    /// Download all cloud data and replace local data
    func downloadAllCloudData(to context: ModelContext) async throws {
        stateManager.syncStatus = .syncing
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        // Fetch cloud data before deleting local data. If iCloud fails here, the
        // local store remains untouched.
        let (vehicleCKRecords, fuelingCKRecords) = try await fetchAllCloudRecords()

        let vehicleDescriptor = FetchDescriptor<Vehicle>()
        let localVehicles = try context.fetch(vehicleDescriptor)
        for vehicle in localVehicles {
            context.delete(vehicle)
        }

        var vehicleMap: [CKRecord.ID: Vehicle] = [:]

        for ckRecord in vehicleCKRecords {
            let vehicle = vehicleFromCKRecord(ckRecord)
            context.insert(vehicle)
            vehicleMap[ckRecord.recordID] = vehicle
        }

        // Build UUID-based lookup from the CKRecord.ID-keyed map
        var vehiclesByUUID: [UUID: Vehicle] = [:]
        for (ckRecordID, vehicle) in vehicleMap {
            if let uuid = UUID(uuidString: ckRecordID.recordName) {
                vehiclesByUUID[uuid] = vehicle
            }
        }

        for ckRecord in fuelingCKRecords {
            if let vehicleUUIDString = ckRecord[CloudFieldKey.FuelingRecord.vehicleRef] as? String,
               let vehicleUUID = UUID(uuidString: vehicleUUIDString),
               let vehicle = vehiclesByUUID[vehicleUUID] {
                let record = fuelingRecordFromCKRecord(ckRecord, vehicle: vehicle)
                context.insert(record)
            }
        }

        try context.save()

        // Rebuild all caches
        StatisticsCacheService.rebuildCacheForAllVehicles(in: context, force: true)

        stateManager.syncStatus = .synced
    }

    // MARK: - Merge Cloud and Local

    /// Merge cloud and local data: match by UUID, keep newer for matches, insert unique from both sides
    func mergeCloudAndLocal(context: ModelContext) async throws {
        stateManager.syncStatus = .syncing
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

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
        // Build local index
        let localVehicles = try context.fetch(FetchDescriptor<Vehicle>())
        var localVehicleMap: [UUID: Vehicle] = [:]
        for v in localVehicles {
            localVehicleMap[v.id] = v
        }

        let localRecords = try context.fetch(FetchDescriptor<FuelingRecord>())
        var localRecordMap: [UUID: FuelingRecord] = [:]
        for r in localRecords {
            localRecordMap[r.id] = r
        }

        var cloudVehicleMap: [UUID: CKRecord] = [:]
        var ckRecordIDToVehicle: [CKRecord.ID: Vehicle] = [:]
        var recordsToUpload: [CKRecord] = []

        for ckRecord in vehicleCKRecords {
            guard let idString = ckRecord[CloudFieldKey.Vehicle.id] as? String,
                  let uuid = UUID(uuidString: idString) else { continue }
            cloudVehicleMap[uuid] = ckRecord

            if let localVehicle = localVehicleMap[uuid] {
                switch Self.resolveConflict(
                    cloudModifiedAt: ckRecord[CloudFieldKey.Vehicle.modifiedAt] as? Date,
                    cloudCreatedAt: ckRecord[CloudFieldKey.Vehicle.createdAt] as? Date,
                    localModifiedAt: localVehicle.modifiedAt,
                    localCreatedAt: localVehicle.createdAt
                ) {
                case .cloud:
                    updateVehicle(localVehicle, from: ckRecord)
                case .local:
                    // Local is newer — push it so other devices are not left stale.
                    recordsToUpload.append(vehicleToCKRecord(localVehicle))
                case .tie:
                    break
                }
                ckRecordIDToVehicle[ckRecord.recordID] = localVehicle
            } else {
                // Only in cloud: insert locally
                let vehicle = vehicleFromCKRecord(ckRecord)
                context.insert(vehicle)
                ckRecordIDToVehicle[ckRecord.recordID] = vehicle
            }
        }

        // Upload local-only vehicles to cloud
        for (uuid, vehicle) in localVehicleMap where cloudVehicleMap[uuid] == nil {
            let ckRecord = vehicleToCKRecord(vehicle)
            recordsToUpload.append(ckRecord)
            ckRecordIDToVehicle[ckRecord.recordID] = vehicle
        }

        // Build a UUID-keyed lookup from ckRecordIDToVehicle for O(1) access
        var vehicleByUUID: [UUID: Vehicle] = [:]
        for vehicle in ckRecordIDToVehicle.values {
            vehicleByUUID[vehicle.id] = vehicle
        }

        var cloudRecordMap: [UUID: CKRecord] = [:]

        for ckRecord in fuelingCKRecords {
            guard let idString = ckRecord[CloudFieldKey.FuelingRecord.id] as? String,
                  let uuid = UUID(uuidString: idString) else { continue }
            cloudRecordMap[uuid] = ckRecord

            if let localRecord = localRecordMap[uuid] {
                switch Self.resolveConflict(
                    cloudModifiedAt: ckRecord[CloudFieldKey.FuelingRecord.modifiedAt] as? Date,
                    cloudCreatedAt: ckRecord[CloudFieldKey.FuelingRecord.createdAt] as? Date,
                    localModifiedAt: localRecord.modifiedAt,
                    localCreatedAt: localRecord.createdAt
                ) {
                case .cloud:
                    updateFuelingRecord(localRecord, from: ckRecord)
                case .local:
                    // Local is newer — push it so other devices are not left stale.
                    let vehicleRecordID = CKRecord.ID(recordName: localRecord.vehicle.id.uuidString, zoneID: zoneID)
                    recordsToUpload.append(fuelingRecordToCKRecord(localRecord, vehicleRecordID: vehicleRecordID))
                case .tie:
                    break
                }
            } else {
                // Only in cloud: insert locally
                if let vehicleUUIDString = ckRecord[CloudFieldKey.FuelingRecord.vehicleRef] as? String,
                   let vehicleUUID = UUID(uuidString: vehicleUUIDString),
                   let vehicle = localVehicleMap[vehicleUUID] ?? vehicleByUUID[vehicleUUID] {
                    let record = fuelingRecordFromCKRecord(ckRecord, vehicle: vehicle)
                    context.insert(record)
                }
            }
        }

        // Upload local-only fueling records to cloud
        for (uuid, record) in localRecordMap where cloudRecordMap[uuid] == nil {
            let vehicleRecordID = CKRecord.ID(recordName: record.vehicle.id.uuidString, zoneID: zoneID)
            let ckRecord = fuelingRecordToCKRecord(record, vehicleRecordID: vehicleRecordID)
            recordsToUpload.append(ckRecord)
        }

        return recordsToUpload
    }

    // MARK: - Delete All Cloud Data

    /// Delete the custom zone (deletes all records in it), then recreate it
    func deleteAllCloudData() async throws {
        stateManager.syncStatus = .syncing

        // Deleting the zone deletes all records in it
        let _ = try await privateDatabase.modifyRecordZones(saving: [], deleting: [zoneID])

        // Recreate the zone for future use
        try await ensureZoneExists()

        // Reset the change token
        stateManager.serverChangeToken = nil
        stateManager.syncStatus = .synced
    }

    // MARK: - Cloud Record Counts

    /// Fetch the number of vehicles and fueling records currently in CloudKit.
    func fetchCloudRecordCounts() async -> (vehicles: Int, fuelingRecords: Int) {
        do {
            let (vehicles, fuelingRecords) = try await fetchAllCloudRecords()
            return (vehicles.count, fuelingRecords.count)
        } catch {
            Self.logger.error("Failed to fetch cloud record counts: \(error)")
            return (0, 0)
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
        var deletedIDs: Set<CKRecord.ID> = []
        var changeToken: CKServerChangeToken? = nil
        var moreComing = true

        while moreComing {
            let results = try await privateDatabase.recordZoneChanges(
                inZoneWith: zoneID,
                since: changeToken
            )

            for (recordID, result) in results.modificationResultsByID {
                if case .success(let modification) = result {
                    let record = modification.record
                    deletedIDs.remove(recordID)
                    switch record.recordType {
                    case RecordType.vehicle:
                        vehicleRecords[recordID] = record
                    case RecordType.fuelingRecord:
                        fuelingRecords[recordID] = record
                    default:
                        break
                    }
                }
            }

            // Track deletions so we don't count deleted records
            for deletion in results.deletions {
                let recordID = deletion.recordID
                deletedIDs.insert(recordID)
                vehicleRecords.removeValue(forKey: recordID)
                fuelingRecords.removeValue(forKey: recordID)
            }

            changeToken = results.changeToken
            moreComing = results.moreComing
        }

        return (Array(vehicleRecords.values), Array(fuelingRecords.values))
    }

    // MARK: - Incremental Push

    /// Push local changes to CloudKit
    func pushChanges(inserted: [any PersistentModel], updated: [any PersistentModel], deleted: [PersistentIdentifier]) async {
        guard stateManager.iCloudSyncEnabled && stateManager.initialSyncCompleted else { return }
        guard !isApplyingRemoteChanges else { return }

        var recordsToSave: [CKRecord] = []

        for model in inserted + updated {
            if let vehicle = model as? Vehicle {
                recordsToSave.append(vehicleToCKRecord(vehicle))
            } else if let record = model as? FuelingRecord {
                let vehicleRecordID = CKRecord.ID(recordName: record.vehicle.id.uuidString, zoneID: zoneID)
                recordsToSave.append(fuelingRecordToCKRecord(record, vehicleRecordID: vehicleRecordID))
            }
        }

        guard !recordsToSave.isEmpty else { return }

        do {
            try await batchSave(records: recordsToSave)
        } catch {
            Self.logger.error("Failed to push changes to CloudKit: \(error)")
        }
    }

    // MARK: - Incremental Pull

    /// Pull remote changes using server change tokens for efficient delta sync
    func pullRemoteChanges(to context: ModelContext) async {
        guard stateManager.iCloudSyncEnabled && stateManager.initialSyncCompleted else { return }

        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

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

    /// Outcome of applying a fetched remote change set to the local store.
    struct RemoteApplyResult {
        /// Local copies that won last-writer-wins against an older cloud copy.
        /// They must be pushed back so the cloud (and other devices) stop
        /// serving the stale value — otherwise devices stay divergent until the
        /// next unrelated local save happens to trigger a push.
        var recordsToUpload: [CKRecord] = []

        /// Fueling records whose parent vehicle could not be resolved (neither
        /// present locally nor in this change set). They are intentionally left
        /// un-applied and reported so the caller can log/diagnose them.
        var unresolvedChildIDs: [UUID] = []
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
        var result = RemoteApplyResult()

        // Build local indexes
        let localVehicles = try context.fetch(FetchDescriptor<Vehicle>())
        var vehicleMap: [UUID: Vehicle] = [:]
        for v in localVehicles {
            vehicleMap[v.id] = v
        }

        let localRecords = try context.fetch(FetchDescriptor<FuelingRecord>())
        var recordMap: [UUID: FuelingRecord] = [:]
        for r in localRecords {
            recordMap[r.id] = r
        }

        // Pass 1 — vehicles first, so any fueling record can resolve its owner.
        for ckRecord in changedRecords where ckRecord.recordType == RecordType.vehicle {
            guard let idString = ckRecord[CloudFieldKey.Vehicle.id] as? String,
                  let uuid = UUID(uuidString: idString) else { continue }

            if let existing = vehicleMap[uuid] {
                switch Self.resolveConflict(
                    cloudModifiedAt: ckRecord[CloudFieldKey.Vehicle.modifiedAt] as? Date,
                    cloudCreatedAt: ckRecord[CloudFieldKey.Vehicle.createdAt] as? Date,
                    localModifiedAt: existing.modifiedAt,
                    localCreatedAt: existing.createdAt
                ) {
                case .cloud:
                    updateVehicle(existing, from: ckRecord)
                case .local:
                    // Local is newer: keep it and push it back so the stale
                    // cloud copy is corrected.
                    result.recordsToUpload.append(vehicleToCKRecord(existing))
                case .tie:
                    break
                }
            } else {
                let vehicle = vehicleFromCKRecord(ckRecord)
                context.insert(vehicle)
                vehicleMap[uuid] = vehicle
            }
        }

        // Pass 2 — fueling records, now guaranteed to see every changed vehicle.
        for ckRecord in changedRecords where ckRecord.recordType == RecordType.fuelingRecord {
            guard let idString = ckRecord[CloudFieldKey.FuelingRecord.id] as? String,
                  let uuid = UUID(uuidString: idString) else { continue }

            if let existing = recordMap[uuid] {
                switch Self.resolveConflict(
                    cloudModifiedAt: ckRecord[CloudFieldKey.FuelingRecord.modifiedAt] as? Date,
                    cloudCreatedAt: ckRecord[CloudFieldKey.FuelingRecord.createdAt] as? Date,
                    localModifiedAt: existing.modifiedAt,
                    localCreatedAt: existing.createdAt
                ) {
                case .cloud:
                    updateFuelingRecord(existing, from: ckRecord)
                case .local:
                    // Local is newer: keep it and push it back so the stale
                    // cloud copy is corrected.
                    let vehicleRecordID = CKRecord.ID(recordName: existing.vehicle.id.uuidString, zoneID: zoneID)
                    result.recordsToUpload.append(fuelingRecordToCKRecord(existing, vehicleRecordID: vehicleRecordID))
                case .tie:
                    break
                }
            } else if let vehicleUUIDString = ckRecord[CloudFieldKey.FuelingRecord.vehicleRef] as? String,
                      let vehicleUUID = UUID(uuidString: vehicleUUIDString),
                      let vehicle = vehicleMap[vehicleUUID] {
                let record = fuelingRecordFromCKRecord(ckRecord, vehicle: vehicle)
                context.insert(record)
                recordMap[uuid] = record
            } else {
                // Parent vehicle is neither local nor in this change set. Leave
                // the cloud copy intact and report the record so the caller holds
                // the change token and retries, instead of skipping the record
                // forever (see `commitPullOutcome`).
                result.unresolvedChildIDs.append(uuid)
            }
        }

        // Apply deletions.
        //
        // Policy: delete-wins. A record deleted on any device is removed here
        // even when the local copy carries a newer edit. CloudKit deletions
        // carry no timestamp, so genuine last-writer-wins for deletes would
        // require persisted tombstones — a schema change we deliberately avoid
        // in this data-critical app. Delete-wins is also the safer default for a
        // single iCloud account's devices: an intentionally deleted fill-up
        // should not be resurrected by a stale edit sitting on another device.
        for recordID in deletedRecordIDs {
            let uuidString = recordID.recordName
            if let uuid = UUID(uuidString: uuidString) {
                if let vehicle = vehicleMap[uuid] {
                    context.delete(vehicle)
                } else if let record = recordMap[uuid] {
                    context.delete(record)
                }
            }
        }

        try context.save()

        // Rebuild caches
        StatisticsCacheService.rebuildCacheForAllVehicles(in: context, force: true)

        return result
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
                  !wasSuppressedWhenSaved,
                  !self.shouldSuppressAutomaticPush else { return }

            Task(priority: .utility) { @MainActor [weak self] in
                guard let self = self else { return }
                await self.pushLocalChangesToCloud(container: container)
            }
        }
    }

    private var shouldSuppressAutomaticPush: Bool {
        isApplyingRemoteChanges || localPushSuspensionCount > 0
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
        await pushLocalChangesToCloud(container: modelContainer)
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
    private func pushLocalChangesToCloud(container: ModelContainer) async {
        guard stateManager.iCloudSyncEnabled && stateManager.initialSyncCompleted else { return }
        guard !shouldSuppressAutomaticPush else { return }

        do {
            stateManager.syncStatus = .syncing

            try await ensureZoneExists()

            let context = container.mainContext
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
            lastPushDate = Date()
            stateManager.syncStatus = .synced
        } catch {
            Self.logger.error("Failed to push local changes to cloud: \(error)")
            stateManager.syncStatus = .error(String(localized: "Sync failed"))
        }
    }

    // MARK: - Conflict Resolution

    /// Which copy wins when the same record exists both locally and in the cloud.
    enum ConflictWinner: Equatable {
        case cloud
        case local
        case tie
    }

    /// Decide which copy of a record is newer using `modifiedAt` with a
    /// `createdAt` fallback.
    ///
    /// Records created before the V1→V2 migration — and any record that has
    /// never been edited — can have a `nil` `modifiedAt`, so we fall back to
    /// `createdAt` instead of treating `nil` as `.distantPast`. Equal effective
    /// timestamps return `.tie`, which every caller treats as "make no change",
    /// keeping repeated syncs stable and never dropping data.
    nonisolated static func resolveConflict(
        cloudModifiedAt: Date?,
        cloudCreatedAt: Date?,
        localModifiedAt: Date?,
        localCreatedAt: Date?
    ) -> ConflictWinner {
        let cloudDate = cloudModifiedAt ?? cloudCreatedAt ?? .distantPast
        let localDate = localModifiedAt ?? localCreatedAt ?? .distantPast
        if cloudDate > localDate { return .cloud }
        if localDate > cloudDate { return .local }
        return .tie
    }

    // MARK: - CKRecord Mapping

    /// Wire-format field keys. Kept `internal` (not `private`) so tests can
    /// assert the exact payload that gets uploaded, using the same source of
    /// truth as production instead of duplicating magic strings.
    enum CloudFieldKey {
        enum Vehicle {
            static let id = "vehicleID"
            static let name = "name"
            static let make = "make"
            static let model = "model"
            static let year = "year"
            static let unitSystemRaw = "unitSystemRaw"
            static let createdAt = "vehicleCreatedAt"
            static let modifiedAt = "vehicleModifiedAt"
        }

        enum FuelingRecord {
            static let id = "fuelingRecordID"
            static let date = "date"
            static let odometer = "odometer"
            static let pricePerFuelUnit = "pricePerFuelUnit"
            static let fuelAmount = "fuelAmount"
            static let totalCost = "totalCost"
            static let fillUpTypeRaw = "fillUpTypeRaw"
            static let notes = "notes"
            static let createdAt = "fuelingCreatedAt"
            static let modifiedAt = "fuelingModifiedAt"
            static let vehicleRef = "vehicleOwnerID"
        }
    }

    /// Convert a Vehicle model to a CKRecord
    func vehicleToCKRecord(_ vehicle: Vehicle) -> CKRecord {
        let recordID = CKRecord.ID(recordName: vehicle.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: RecordType.vehicle, recordID: recordID)

        record[CloudFieldKey.Vehicle.id] = vehicle.id.uuidString
        record[CloudFieldKey.Vehicle.name] = vehicle.name
        record[CloudFieldKey.Vehicle.make] = vehicle.make
        record[CloudFieldKey.Vehicle.model] = vehicle.model
        record[CloudFieldKey.Vehicle.year] = vehicle.year as? CKRecordValue
        record[CloudFieldKey.Vehicle.unitSystemRaw] = vehicle.unitSystemRaw
        record[CloudFieldKey.Vehicle.createdAt] = vehicle.createdAt
        record[CloudFieldKey.Vehicle.modifiedAt] = vehicle.modifiedAt

        return record
    }

    /// Convert a CKRecord to a Vehicle model
    private func vehicleFromCKRecord(_ ckRecord: CKRecord) -> Vehicle {
        let id = UUID(uuidString: ckRecord[CloudFieldKey.Vehicle.id] as? String ?? "") ?? UUID()
        let name = ckRecord[CloudFieldKey.Vehicle.name] as? String ?? ""
        let make = ckRecord[CloudFieldKey.Vehicle.make] as? String
        let model = ckRecord[CloudFieldKey.Vehicle.model] as? String
        let year = ckRecord[CloudFieldKey.Vehicle.year] as? Int
        let unitSystemRaw = ckRecord[CloudFieldKey.Vehicle.unitSystemRaw] as? String ?? UnitSystem.imperial.rawValue
        let createdAt = ckRecord[CloudFieldKey.Vehicle.createdAt] as? Date ?? Date()

        let vehicle = Vehicle(
            id: id,
            name: name,
            make: make,
            model: model,
            year: year,
            createdAt: createdAt,
            unitSystem: UnitSystem(rawValue: unitSystemRaw) ?? .imperial
        )
        vehicle.modifiedAt = ckRecord[CloudFieldKey.Vehicle.modifiedAt] as? Date

        return vehicle
    }

    /// Update an existing Vehicle from a CKRecord
    private func updateVehicle(_ vehicle: Vehicle, from ckRecord: CKRecord) {
        vehicle.name = ckRecord[CloudFieldKey.Vehicle.name] as? String ?? vehicle.name
        vehicle.make = ckRecord[CloudFieldKey.Vehicle.make] as? String
        vehicle.model = ckRecord[CloudFieldKey.Vehicle.model] as? String
        vehicle.year = ckRecord[CloudFieldKey.Vehicle.year] as? Int
        vehicle.unitSystemRaw = ckRecord[CloudFieldKey.Vehicle.unitSystemRaw] as? String ?? vehicle.unitSystemRaw
        vehicle.modifiedAt = ckRecord[CloudFieldKey.Vehicle.modifiedAt] as? Date
    }

    /// Convert a FuelingRecord model to a CKRecord
    func fuelingRecordToCKRecord(_ fuelingRecord: FuelingRecord, vehicleRecordID: CKRecord.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: fuelingRecord.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: RecordType.fuelingRecord, recordID: recordID)

        record[CloudFieldKey.FuelingRecord.id] = fuelingRecord.id.uuidString
        record[CloudFieldKey.FuelingRecord.date] = fuelingRecord.date
        record[CloudFieldKey.FuelingRecord.odometer] = fuelingRecord.odometer
        record[CloudFieldKey.FuelingRecord.pricePerFuelUnit] = fuelingRecord.pricePerFuelUnit
        record[CloudFieldKey.FuelingRecord.fuelAmount] = fuelingRecord.fuelAmount
        record[CloudFieldKey.FuelingRecord.totalCost] = fuelingRecord.totalCost
        record[CloudFieldKey.FuelingRecord.fillUpTypeRaw] = fuelingRecord.fillUpTypeRaw
        record[CloudFieldKey.FuelingRecord.notes] = fuelingRecord.notes
        record[CloudFieldKey.FuelingRecord.createdAt] = fuelingRecord.createdAt
        record[CloudFieldKey.FuelingRecord.modifiedAt] = fuelingRecord.modifiedAt

        // Store parent vehicle ID as plain string (avoids CloudKit's 750 owning-reference limit)
        record[CloudFieldKey.FuelingRecord.vehicleRef] = vehicleRecordID.recordName

        return record
    }

    /// Convert a CKRecord to a FuelingRecord model
    private func fuelingRecordFromCKRecord(_ ckRecord: CKRecord, vehicle: Vehicle) -> FuelingRecord {
        let id = UUID(uuidString: ckRecord[CloudFieldKey.FuelingRecord.id] as? String ?? "") ?? UUID()
        let date = ckRecord[CloudFieldKey.FuelingRecord.date] as? Date ?? Date()
        let odometer = ckRecord[CloudFieldKey.FuelingRecord.odometer] as? Double ?? 0
        let pricePerFuelUnit = ckRecord[CloudFieldKey.FuelingRecord.pricePerFuelUnit] as? Double ?? 0
        let fuelAmount = ckRecord[CloudFieldKey.FuelingRecord.fuelAmount] as? Double ?? 0
        let totalCost = ckRecord[CloudFieldKey.FuelingRecord.totalCost] as? Double ?? 0
        let fillUpTypeRaw = ckRecord[CloudFieldKey.FuelingRecord.fillUpTypeRaw] as? String ?? FillUpType.full.rawValue
        let notes = ckRecord[CloudFieldKey.FuelingRecord.notes] as? String
        let createdAt = ckRecord[CloudFieldKey.FuelingRecord.createdAt] as? Date ?? Date()

        let record = FuelingRecord(
            id: id,
            date: date,
            odometer: odometer,
            pricePerFuelUnit: pricePerFuelUnit,
            fuelAmount: fuelAmount,
            totalCost: totalCost,
            fillUpType: FillUpType(rawValue: fillUpTypeRaw) ?? .full,
            notes: notes,
            createdAt: createdAt,
            vehicle: vehicle
        )
        record.modifiedAt = ckRecord[CloudFieldKey.FuelingRecord.modifiedAt] as? Date
        return record
    }

    /// Update an existing FuelingRecord from a CKRecord
    private func updateFuelingRecord(_ record: FuelingRecord, from ckRecord: CKRecord) {
        record.date = ckRecord[CloudFieldKey.FuelingRecord.date] as? Date ?? record.date
        record.odometer = ckRecord[CloudFieldKey.FuelingRecord.odometer] as? Double ?? record.odometer
        record.pricePerFuelUnit = ckRecord[CloudFieldKey.FuelingRecord.pricePerFuelUnit] as? Double ?? record.pricePerFuelUnit
        record.fuelAmount = ckRecord[CloudFieldKey.FuelingRecord.fuelAmount] as? Double ?? record.fuelAmount
        record.totalCost = ckRecord[CloudFieldKey.FuelingRecord.totalCost] as? Double ?? record.totalCost
        record.fillUpTypeRaw = ckRecord[CloudFieldKey.FuelingRecord.fillUpTypeRaw] as? String ?? record.fillUpTypeRaw
        record.notes = ckRecord[CloudFieldKey.FuelingRecord.notes] as? String
        record.modifiedAt = ckRecord[CloudFieldKey.FuelingRecord.modifiedAt] as? Date
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
