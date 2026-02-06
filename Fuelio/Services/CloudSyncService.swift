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
                stateManager.syncStatus = .error("Failed to check iCloud status")
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

        // Clear all local data first
        let vehicleDescriptor = FetchDescriptor<Vehicle>()
        let localVehicles = try context.fetch(vehicleDescriptor)
        for vehicle in localVehicles {
            context.delete(vehicle)
        }
        try context.save()

        // Fetch all cloud records using change token (avoids queryable field requirements)
        let (vehicleCKRecords, fuelingCKRecords) = try await fetchAllCloudRecords()

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
        StatisticsCacheService.rebuildCacheForAllVehicles(in: context)

        stateManager.syncStatus = .synced
    }

    // MARK: - Merge Cloud and Local

    /// Merge cloud and local data: match by UUID, keep newer for matches, insert unique from both sides
    func mergeCloudAndLocal(context: ModelContext) async throws {
        stateManager.syncStatus = .syncing
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        // Build local index
        let vehicleDescriptor = FetchDescriptor<Vehicle>()
        let localVehicles = try context.fetch(vehicleDescriptor)
        var localVehicleMap: [UUID: Vehicle] = [:]
        for v in localVehicles {
            localVehicleMap[v.id] = v
        }

        var localRecordMap: [UUID: FuelingRecord] = [:]
        let recordDescriptor = FetchDescriptor<FuelingRecord>()
        let localRecords = try context.fetch(recordDescriptor)
        for r in localRecords {
            localRecordMap[r.id] = r
        }

        // Fetch all cloud records using change token (avoids queryable field requirements)
        let (vehicleCKRecords, fuelingCKRecords) = try await fetchAllCloudRecords()

        var cloudVehicleMap: [UUID: CKRecord] = [:]
        var ckRecordIDToVehicle: [CKRecord.ID: Vehicle] = [:]

        for ckRecord in vehicleCKRecords {
            if let idString = ckRecord[CloudFieldKey.Vehicle.id] as? String,
               let uuid = UUID(uuidString: idString) {
                cloudVehicleMap[uuid] = ckRecord

                if let localVehicle = localVehicleMap[uuid] {
                    // Both exist: keep newer
                    let cloudDate = ckRecord[CloudFieldKey.Vehicle.createdAt] as? Date ?? Date.distantPast
                    if cloudDate > localVehicle.createdAt {
                        // Cloud is newer -- update local
                        updateVehicle(localVehicle, from: ckRecord)
                    }
                    ckRecordIDToVehicle[ckRecord.recordID] = localVehicle
                } else {
                    // Only in cloud: insert locally
                    let vehicle = vehicleFromCKRecord(ckRecord)
                    context.insert(vehicle)
                    ckRecordIDToVehicle[ckRecord.recordID] = vehicle
                }
            }
        }

        // Upload local-only vehicles to cloud
        var recordsToUpload: [CKRecord] = []
        for (uuid, vehicle) in localVehicleMap where cloudVehicleMap[uuid] == nil {
            let ckRecord = vehicleToCKRecord(vehicle)
            recordsToUpload.append(ckRecord)
            ckRecordIDToVehicle[ckRecord.recordID] = vehicle
        }

        var cloudRecordMap: [UUID: CKRecord] = [:]

        for ckRecord in fuelingCKRecords {
            if let idString = ckRecord[CloudFieldKey.FuelingRecord.id] as? String,
               let uuid = UUID(uuidString: idString) {
                cloudRecordMap[uuid] = ckRecord

                if let localRecord = localRecordMap[uuid] {
                    // Both exist: keep newer
                    let cloudDate = ckRecord[CloudFieldKey.FuelingRecord.createdAt] as? Date ?? Date.distantPast
                    if cloudDate > localRecord.createdAt {
                        updateFuelingRecord(localRecord, from: ckRecord)
                    }
                } else {
                    // Only in cloud: insert locally
                    if let vehicleUUIDString = ckRecord[CloudFieldKey.FuelingRecord.vehicleRef] as? String,
                       let vehicleUUID = UUID(uuidString: vehicleUUIDString),
                       let vehicle = localVehicleMap[vehicleUUID] ?? ckRecordIDToVehicle.values.first(where: { $0.id == vehicleUUID }) {
                        let record = fuelingRecordFromCKRecord(ckRecord, vehicle: vehicle)
                        context.insert(record)
                    }
                }
            }
        }

        // Upload local-only fueling records to cloud
        for (uuid, record) in localRecordMap where cloudRecordMap[uuid] == nil {
            let vehicleRecordID = CKRecord.ID(recordName: record.vehicle.id.uuidString, zoneID: zoneID)
            let ckRecord = fuelingRecordToCKRecord(record, vehicleRecordID: vehicleRecordID)
            recordsToUpload.append(ckRecord)
        }

        // Batch upload
        if !recordsToUpload.isEmpty {
            try await batchSave(records: recordsToUpload)
        }

        try context.save()

        // Rebuild all caches
        StatisticsCacheService.rebuildCacheForAllVehicles(in: context)

        stateManager.syncStatus = .synced
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

            let results = try await privateDatabase.recordZoneChanges(
                inZoneWith: zoneID,
                since: stateManager.serverChangeToken
            )

            for (_, result) in results.modificationResultsByID {
                if case .success(let modification) = result {
                    changedRecords.append(modification.record)
                }
            }

            for deletion in results.deletions {
                deletedRecordIDs.append(deletion.recordID)
            }

            // Apply changes locally
            try applyRemoteChanges(changedRecords: changedRecords, deletedRecordIDs: deletedRecordIDs, context: context)

            // Update the change token
            stateManager.serverChangeToken = results.changeToken

            stateManager.syncStatus = .synced
        } catch {
            Self.logger.error("Failed to pull remote changes: \(error)")
            stateManager.syncStatus = .error("Pull failed")
        }
    }

    /// Apply fetched remote changes to the local store
    private func applyRemoteChanges(changedRecords: [CKRecord], deletedRecordIDs: [CKRecord.ID], context: ModelContext) throws {
        // Build local indexes
        let vehicleDescriptor = FetchDescriptor<Vehicle>()
        let localVehicles = try context.fetch(vehicleDescriptor)
        var vehicleMap: [UUID: Vehicle] = [:]
        for v in localVehicles {
            vehicleMap[v.id] = v
        }

        let recordDescriptor = FetchDescriptor<FuelingRecord>()
        let localRecords = try context.fetch(recordDescriptor)
        var recordMap: [UUID: FuelingRecord] = [:]
        for r in localRecords {
            recordMap[r.id] = r
        }

        // Apply changes
        for ckRecord in changedRecords {
            switch ckRecord.recordType {
            case RecordType.vehicle:
                if let idString = ckRecord[CloudFieldKey.Vehicle.id] as? String,
                   let uuid = UUID(uuidString: idString) {
                    if let existing = vehicleMap[uuid] {
                        updateVehicle(existing, from: ckRecord)
                    } else {
                        let vehicle = vehicleFromCKRecord(ckRecord)
                        context.insert(vehicle)
                        vehicleMap[uuid] = vehicle
                    }
                }

            case RecordType.fuelingRecord:
                if let idString = ckRecord[CloudFieldKey.FuelingRecord.id] as? String,
                   let uuid = UUID(uuidString: idString) {
                    if let existing = recordMap[uuid] {
                        updateFuelingRecord(existing, from: ckRecord)
                    } else if let vehicleUUIDString = ckRecord[CloudFieldKey.FuelingRecord.vehicleRef] as? String,
                              let vehicleUUID = UUID(uuidString: vehicleUUIDString),
                              let vehicle = vehicleMap[vehicleUUID] {
                        let record = fuelingRecordFromCKRecord(ckRecord, vehicle: vehicle)
                        context.insert(record)
                    }
                }

            default:
                break
            }
        }

        // Apply deletions
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
        StatisticsCacheService.rebuildCacheForAllVehicles(in: context)
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

        // Observe managed object context saves
        saveObserver = NotificationCenter.default.publisher(
            for: Notification.Name.NSManagedObjectContextDidSave
        )
        .debounce(for: .seconds(Self.saveDebounceInterval), scheduler: RunLoop.main)
        .sink { [weak self] notification in
            guard let self = self, !self.isApplyingRemoteChanges else { return }

            // Use .utility priority so the Swift runtime schedules UI-interactive
            // work (sheet transitions, list updates) ahead of the sync task.
            Task(priority: .utility) { @MainActor [weak self] in
                guard let self = self else { return }
                let context = container.mainContext
                // On local save, do an incremental push
                // We can't easily get the specific changes from the notification with SwiftData,
                // so we rely on the server change token mechanism to identify what's new
                await self.pushAllLocalData(context: context)
            }
        }
    }

    /// Stop monitoring local saves
    func stopMonitoring() {
        saveObserver?.cancel()
        saveObserver = nil
        modelContainer = nil
    }

    /// Push all local data (simplified incremental push)
    private func pushAllLocalData(context: ModelContext) async {
        guard stateManager.iCloudSyncEnabled && stateManager.initialSyncCompleted else { return }
        guard !isApplyingRemoteChanges else { return }

        do {
            try await uploadAllLocalData(from: context)
        } catch {
            Self.logger.error("Failed to push local data: \(error)")
        }
    }

    // MARK: - CKRecord Mapping

    private enum CloudFieldKey {
        enum Vehicle {
            static let id = "vehicleID"
            static let name = "name"
            static let make = "make"
            static let model = "model"
            static let year = "year"
            static let unitSystemRaw = "unitSystemRaw"
            static let createdAt = "vehicleCreatedAt"
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
            static let vehicleRef = "vehicleOwnerID"
        }
    }

    /// Convert a Vehicle model to a CKRecord
    private func vehicleToCKRecord(_ vehicle: Vehicle) -> CKRecord {
        let recordID = CKRecord.ID(recordName: vehicle.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: RecordType.vehicle, recordID: recordID)

        record[CloudFieldKey.Vehicle.id] = vehicle.id.uuidString
        record[CloudFieldKey.Vehicle.name] = vehicle.name
        record[CloudFieldKey.Vehicle.make] = vehicle.make
        record[CloudFieldKey.Vehicle.model] = vehicle.model
        record[CloudFieldKey.Vehicle.year] = vehicle.year as? CKRecordValue
        record[CloudFieldKey.Vehicle.unitSystemRaw] = vehicle.unitSystemRaw
        record[CloudFieldKey.Vehicle.createdAt] = vehicle.createdAt

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

        return vehicle
    }

    /// Update an existing Vehicle from a CKRecord
    private func updateVehicle(_ vehicle: Vehicle, from ckRecord: CKRecord) {
        vehicle.name = ckRecord[CloudFieldKey.Vehicle.name] as? String ?? vehicle.name
        vehicle.make = ckRecord[CloudFieldKey.Vehicle.make] as? String
        vehicle.model = ckRecord[CloudFieldKey.Vehicle.model] as? String
        vehicle.year = ckRecord[CloudFieldKey.Vehicle.year] as? Int
        vehicle.unitSystemRaw = ckRecord[CloudFieldKey.Vehicle.unitSystemRaw] as? String ?? vehicle.unitSystemRaw
    }

    /// Convert a FuelingRecord model to a CKRecord
    private func fuelingRecordToCKRecord(_ fuelingRecord: FuelingRecord, vehicleRecordID: CKRecord.ID) -> CKRecord {
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

        return FuelingRecord(
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
}
