import XCTest
import CloudKit
import SwiftData
@testable import PumpTally

/// Tests for the CloudKit conflict-resolution and reconciliation logic.
///
/// These exercise the pure decision helper plus the two seams that previously
/// caused silent data loss:
///  - `applyRemoteChanges` (incremental pull): ordering + last-writer-wins.
///  - `reconcileMerge` (first-time "Merge Both"): uploading local-newer records.
///
/// Everything here runs against an in-memory SwiftData store and constructs
/// CKRecords directly, so no network or iCloud account is required.
@MainActor
final class CloudSyncServiceTests: XCTestCase {

    // MARK: - Fixtures

    private let t1 = Date(timeIntervalSince1970: 1_000_000)
    private let t2 = Date(timeIntervalSince1970: 2_000_000)
    private let t3 = Date(timeIntervalSince1970: 3_000_000)

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeService() -> CloudSyncService {
        CloudSyncService(stateManager: SyncStateManager())
    }

    private func makeVehicle(
        id: UUID = UUID(),
        name: String,
        createdAt: Date,
        modifiedAt: Date?
    ) -> Vehicle {
        let v = Vehicle(id: id, name: name, createdAt: createdAt)
        v.modifiedAt = modifiedAt
        return v
    }

    private func makeRecord(
        id: UUID = UUID(),
        odometer: Double,
        createdAt: Date,
        modifiedAt: Date?,
        vehicle: Vehicle
    ) -> FuelingRecord {
        let r = FuelingRecord(
            id: id,
            date: createdAt,
            odometer: odometer,
            pricePerFuelUnit: 3.0,
            fuelAmount: 10.0,
            totalCost: 30.0,
            fillUpType: .full,
            createdAt: createdAt,
            vehicle: vehicle
        )
        r.modifiedAt = modifiedAt
        return r
    }

    // MARK: - Transactional cloud replacement

    func testReplaceLocalData_validSnapshotReplacesEverything() throws {
        let service = makeService()
        let context = try makeContext()

        let oldVehicle = makeVehicle(name: "Local Only", createdAt: t1, modifiedAt: t1)
        context.insert(oldVehicle)
        context.insert(makeRecord(odometer: 100, createdAt: t1, modifiedAt: t1, vehicle: oldVehicle))
        try context.save()

        let cloudVehicle = makeVehicle(name: "Cloud Car", createdAt: t2, modifiedAt: t3)
        let cloudRecord = makeRecord(odometer: 500, createdAt: t2, modifiedAt: t3, vehicle: cloudVehicle)
        let cloudVehicleCK = service.vehicleToCKRecord(cloudVehicle)
        let cloudRecordCK = service.fuelingRecordToCKRecord(
            cloudRecord,
            vehicleRecordID: cloudVehicleCK.recordID
        )

        try service.replaceLocalData(
            vehicleCKRecords: [cloudVehicleCK],
            fuelingCKRecords: [cloudRecordCK],
            context: context
        )

        let vehicles = try context.fetch(FetchDescriptor<Vehicle>())
        let records = try context.fetch(FetchDescriptor<FuelingRecord>())
        XCTAssertEqual(vehicles.map(\.id), [cloudVehicle.id])
        XCTAssertEqual(vehicles.first?.name, "Cloud Car")
        XCTAssertEqual(records.map(\.id), [cloudRecord.id])
        XCTAssertEqual(records.first?.odometer, 500)
        XCTAssertEqual(records.first?.vehicle.id, cloudVehicle.id)
    }

    func testReplaceLocalData_invalidSnapshotPreservesLocalStore() throws {
        let service = makeService()
        let context = try makeContext()

        let localVehicle = makeVehicle(name: "Irreplaceable Local", createdAt: t1, modifiedAt: t2)
        context.insert(localVehicle)
        let localRecord = makeRecord(odometer: 321, createdAt: t1, modifiedAt: t2, vehicle: localVehicle)
        context.insert(localRecord)
        try context.save()

        // Structurally valid record, but its parent is absent from the proposed
        // cloud snapshot. Validation must fail before deleting local models.
        let absentVehicle = makeVehicle(name: "Missing Parent", createdAt: t1, modifiedAt: t1)
        let orphan = makeRecord(odometer: 999, createdAt: t1, modifiedAt: t1, vehicle: absentVehicle)
        let orphanCK = service.fuelingRecordToCKRecord(
            orphan,
            vehicleRecordID: service.vehicleToCKRecord(absentVehicle).recordID
        )

        XCTAssertThrowsError(
            try service.replaceLocalData(
                vehicleCKRecords: [],
                fuelingCKRecords: [orphanCK],
                context: context
            )
        )

        let vehicles = try context.fetch(FetchDescriptor<Vehicle>())
        let records = try context.fetch(FetchDescriptor<FuelingRecord>())
        XCTAssertEqual(vehicles.map(\.id), [localVehicle.id])
        XCTAssertEqual(vehicles.first?.name, "Irreplaceable Local")
        XCTAssertEqual(records.map(\.id), [localRecord.id])
        XCTAssertEqual(records.first?.odometer, 321)
    }

    // MARK: - resolveConflict (pure decision, incl. nil-modifiedAt legacy data)

    func testResolveConflict_cloudModifiedNewer_cloudWins() {
        XCTAssertEqual(
            CloudSyncService.resolveConflict(cloudModifiedAt: t3, cloudCreatedAt: t1, localModifiedAt: t2, localCreatedAt: t1),
            .cloud
        )
    }

    func testResolveConflict_localModifiedNewer_localWins() {
        XCTAssertEqual(
            CloudSyncService.resolveConflict(cloudModifiedAt: t2, cloudCreatedAt: t1, localModifiedAt: t3, localCreatedAt: t1),
            .local
        )
    }

    func testResolveConflict_equalModified_isTie() {
        XCTAssertEqual(
            CloudSyncService.resolveConflict(cloudModifiedAt: t2, cloudCreatedAt: t1, localModifiedAt: t2, localCreatedAt: t1),
            .tie
        )
    }

    func testResolveConflict_nilModified_fallsBackToCreatedAt() {
        XCTAssertEqual(
            CloudSyncService.resolveConflict(cloudModifiedAt: nil, cloudCreatedAt: t2, localModifiedAt: nil, localCreatedAt: t1),
            .cloud
        )
        XCTAssertEqual(
            CloudSyncService.resolveConflict(cloudModifiedAt: nil, cloudCreatedAt: t1, localModifiedAt: nil, localCreatedAt: t1),
            .tie
        )
    }

    func testResolveConflict_legacyLocalNilModified_vs_cloudEdit_cloudWins() {
        // Legacy local record (never edited → nil modifiedAt) vs a genuine remote edit.
        XCTAssertEqual(
            CloudSyncService.resolveConflict(cloudModifiedAt: t2, cloudCreatedAt: t1, localModifiedAt: nil, localCreatedAt: t1),
            .cloud
        )
    }

    func testResolveConflict_localEdit_vs_legacyCloudNilModified_localWins() {
        XCTAssertEqual(
            CloudSyncService.resolveConflict(cloudModifiedAt: nil, cloudCreatedAt: t1, localModifiedAt: t2, localCreatedAt: t1),
            .local
        )
    }

    func testResolveConflict_allNil_isTie() {
        XCTAssertEqual(
            CloudSyncService.resolveConflict(cloudModifiedAt: nil, cloudCreatedAt: nil, localModifiedAt: nil, localCreatedAt: nil),
            .tie
        )
    }

    // MARK: - #3: pull ordering must not drop records

    func testApplyRemoteChanges_recordBeforeItsNewVehicle_isNotDropped() throws {
        let service = makeService()
        let context = try makeContext()

        // A brand-new vehicle + its record, neither present locally yet.
        let vehicle = makeVehicle(name: "New Car", createdAt: t1, modifiedAt: t1)
        let record = makeRecord(odometer: 100, createdAt: t1, modifiedAt: t1, vehicle: vehicle)

        let vehicleCK = service.vehicleToCKRecord(vehicle)
        let recordCK = service.fuelingRecordToCKRecord(record, vehicleRecordID: vehicleCK.recordID)

        // Deliberately place the fueling record BEFORE its parent vehicle.
        try service.applyRemoteChanges(
            changedRecords: [recordCK, vehicleCK],
            deletedRecordIDs: [],
            context: context
        )

        let vehicles = try context.fetch(FetchDescriptor<Vehicle>())
        let records = try context.fetch(FetchDescriptor<FuelingRecord>())
        XCTAssertEqual(vehicles.count, 1)
        XCTAssertEqual(records.count, 1, "Record must survive even when it precedes its new vehicle in the change set")
        XCTAssertEqual(records.first?.vehicle.id, vehicle.id)
    }

    // MARK: - #2: last-writer-wins on incremental pull

    func testApplyRemoteChanges_olderCloudDoesNotClobberNewerLocal() throws {
        let service = makeService()
        let context = try makeContext()

        let local = makeVehicle(name: "Local Name", createdAt: t1, modifiedAt: t2)
        context.insert(local)
        try context.save()

        // Older cloud copy (t1) with a different name.
        let cloudCopy = makeVehicle(id: local.id, name: "Old Cloud Name", createdAt: t1, modifiedAt: t1)
        let cloudCK = service.vehicleToCKRecord(cloudCopy)

        let result = try service.applyRemoteChanges(changedRecords: [cloudCK], deletedRecordIDs: [], context: context)

        let vehicles = try context.fetch(FetchDescriptor<Vehicle>())
        XCTAssertEqual(vehicles.count, 1)
        XCTAssertEqual(vehicles.first?.name, "Local Name", "Older cloud copy must not overwrite the newer local edit")

        // The local winner must be queued for upload (with local payload) so the
        // stale cloud copy is corrected instead of leaving devices divergent.
        let uploaded = result.recordsToUpload.first { $0.recordID.recordName == local.id.uuidString }
        XCTAssertNotNil(uploaded, "Local-newer vehicle must be pushed back during pull")
        XCTAssertEqual(uploaded?[CloudSyncService.CloudFieldKey.Vehicle.name] as? String, "Local Name")
        XCTAssertEqual(uploaded?[CloudSyncService.CloudFieldKey.Vehicle.modifiedAt] as? Date, t2)
    }

    func testApplyRemoteChanges_newerCloudOverwritesLocal() throws {
        let service = makeService()
        let context = try makeContext()

        let local = makeVehicle(name: "Local Name", createdAt: t1, modifiedAt: t1)
        context.insert(local)
        try context.save()

        let cloudCopy = makeVehicle(id: local.id, name: "Newer Cloud Name", createdAt: t1, modifiedAt: t3)
        let cloudCK = service.vehicleToCKRecord(cloudCopy)

        let result = try service.applyRemoteChanges(changedRecords: [cloudCK], deletedRecordIDs: [], context: context)

        let vehicles = try context.fetch(FetchDescriptor<Vehicle>())
        XCTAssertEqual(vehicles.first?.name, "Newer Cloud Name")
        XCTAssertTrue(result.recordsToUpload.isEmpty, "When the cloud copy wins there is nothing to push back")
    }

    func testApplyRemoteChanges_legacyLocalNilModified_acceptsCloudEdit() throws {
        let service = makeService()
        let context = try makeContext()

        // Legacy record migrated from V1: modifiedAt == nil.
        let local = makeVehicle(name: "Legacy Local", createdAt: t1, modifiedAt: nil)
        context.insert(local)
        try context.save()

        let cloudCopy = makeVehicle(id: local.id, name: "Cloud Edit", createdAt: t1, modifiedAt: t2)
        let cloudCK = service.vehicleToCKRecord(cloudCopy)

        try service.applyRemoteChanges(changedRecords: [cloudCK], deletedRecordIDs: [], context: context)

        let vehicles = try context.fetch(FetchDescriptor<Vehicle>())
        XCTAssertEqual(vehicles.first?.name, "Cloud Edit", "A genuine remote edit must win over a legacy nil-modifiedAt local copy")
    }

    func testApplyRemoteChanges_fuelingRecord_olderCloudDoesNotClobberNewerLocal_andIsQueued() throws {
        let service = makeService()
        let context = try makeContext()

        let vehicle = makeVehicle(name: "Car", createdAt: t1, modifiedAt: t1)
        context.insert(vehicle)
        let local = makeRecord(odometer: 500, createdAt: t1, modifiedAt: t2, vehicle: vehicle)
        context.insert(local)
        try context.save()

        // Older cloud copy of the same fueling record with a different odometer.
        let cloudCopy = makeRecord(id: local.id, odometer: 999, createdAt: t1, modifiedAt: t1, vehicle: vehicle)
        let vehicleRecordID = service.vehicleToCKRecord(vehicle).recordID
        let cloudCK = service.fuelingRecordToCKRecord(cloudCopy, vehicleRecordID: vehicleRecordID)

        let result = try service.applyRemoteChanges(changedRecords: [cloudCK], deletedRecordIDs: [], context: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<FuelingRecord>()).first?.odometer, 500,
                       "Older cloud fueling record must not overwrite the newer local edit")
        let uploaded = result.recordsToUpload.first { $0.recordID.recordName == local.id.uuidString }
        XCTAssertNotNil(uploaded, "Local-newer fueling record must be pushed back during pull")
        XCTAssertEqual(uploaded?[CloudSyncService.CloudFieldKey.FuelingRecord.odometer] as? Double, 500)
    }

    func testApplyRemoteChanges_fuelingRecord_newerCloudOverwritesLocal() throws {
        let service = makeService()
        let context = try makeContext()

        let vehicle = makeVehicle(name: "Car", createdAt: t1, modifiedAt: t1)
        context.insert(vehicle)
        let local = makeRecord(odometer: 500, createdAt: t1, modifiedAt: t1, vehicle: vehicle)
        context.insert(local)
        try context.save()

        let cloudCopy = makeRecord(id: local.id, odometer: 777, createdAt: t1, modifiedAt: t3, vehicle: vehicle)
        let vehicleRecordID = service.vehicleToCKRecord(vehicle).recordID
        let cloudCK = service.fuelingRecordToCKRecord(cloudCopy, vehicleRecordID: vehicleRecordID)

        let result = try service.applyRemoteChanges(changedRecords: [cloudCK], deletedRecordIDs: [], context: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<FuelingRecord>()).first?.odometer, 777,
                       "Newer cloud fueling record must overwrite the older local copy")
        XCTAssertTrue(result.recordsToUpload.isEmpty, "When the cloud copy wins there is nothing to push back")
    }

    // MARK: - Unresolvable-parent children are reported, not silently dropped

    func testApplyRemoteChanges_recordWithUnresolvableParent_isSkippedAndReported() throws {
        let service = makeService()
        let context = try makeContext()

        // A fueling record whose parent vehicle is neither present locally nor
        // in this change set (mimics the parent's fetch failing during a pull).
        let absentVehicle = makeVehicle(name: "Absent", createdAt: t1, modifiedAt: t1)
        let orphan = makeRecord(odometer: 100, createdAt: t1, modifiedAt: t1, vehicle: absentVehicle)
        let orphanCK = service.fuelingRecordToCKRecord(
            orphan,
            vehicleRecordID: CKRecord.ID(recordName: absentVehicle.id.uuidString)
        )

        let result = try service.applyRemoteChanges(changedRecords: [orphanCK], deletedRecordIDs: [], context: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<FuelingRecord>()).isEmpty,
                      "A record whose parent cannot be resolved must not be inserted")
        XCTAssertEqual(result.unresolvedChildIDs, [orphan.id],
                       "The unresolved child must be reported so the caller can hold the change token and retry")
    }

    // MARK: - Deletions follow an explicit delete-wins policy

    func testApplyRemoteChanges_remoteDeletion_removesLocalRecordEvenIfNewer_deleteWins() throws {
        let service = makeService()
        let context = try makeContext()

        let vehicle = makeVehicle(name: "Car", createdAt: t1, modifiedAt: t1)
        context.insert(vehicle)
        // Local record carries a NEWER edit (t3) than the cloud ever saw.
        let local = makeRecord(odometer: 500, createdAt: t1, modifiedAt: t3, vehicle: vehicle)
        context.insert(local)
        try context.save()

        let deletionID = CKRecord.ID(recordName: local.id.uuidString)
        try service.applyRemoteChanges(changedRecords: [], deletedRecordIDs: [deletionID], context: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<FuelingRecord>()).isEmpty,
                      "Delete-wins policy: a remote deletion removes the local record even when it has a newer edit")
    }

    // MARK: - Pull orchestration: the change token advances only when the window applied safely

    /// End-to-end (network-free) check that the pull sequence
    /// `applyRemoteChanges` → `commitPullOutcome` holds the stored change token
    /// when a child's parent could not be resolved, so the record is retried
    /// rather than skipped forever.
    func testPullOrchestration_unresolvedChild_holdsStoredToken() throws {
        let stateManager = SyncStateManager()
        stateManager.serverChangeToken = nil // known clean starting state
        let service = CloudSyncService(stateManager: stateManager)
        let context = try makeContext()

        // A fueling record whose parent vehicle is absent from both the local
        // store and the change set (mimics the parent's fetch failing).
        let absentVehicle = makeVehicle(name: "Absent", createdAt: t1, modifiedAt: t1)
        let orphan = makeRecord(odometer: 100, createdAt: t1, modifiedAt: t1, vehicle: absentVehicle)
        let orphanCK = service.fuelingRecordToCKRecord(
            orphan,
            vehicleRecordID: CKRecord.ID(recordName: absentVehicle.id.uuidString)
        )

        // Drive the same post-fetch sequence pullRemoteChanges uses.
        let applyResult = try service.applyRemoteChanges(
            changedRecords: [orphanCK],
            deletedRecordIDs: [],
            context: context
        )
        let didAdvance = service.commitPullOutcome(
            fetchedToken: nil,
            hadFetchFailure: false,
            unresolvedChildIDs: applyResult.unresolvedChildIDs
        )

        XCTAssertEqual(applyResult.unresolvedChildIDs, [orphan.id])
        XCTAssertFalse(didAdvance, "Token must not advance while a child's parent is unresolved")
        XCTAssertNil(stateManager.serverChangeToken, "Stored change token must remain unchanged for unresolved children")
        XCTAssertEqual(stateManager.syncStatus, .error(String(localized: "Pull incomplete — will retry")))
    }

    func testCommitPullOutcome_advancesOnlyWhenWindowFullyApplied() {
        let stateManager = SyncStateManager()
        stateManager.serverChangeToken = nil
        let service = CloudSyncService(stateManager: stateManager)

        // Held on unresolved children, on fetch failure, or on both.
        XCTAssertFalse(service.commitPullOutcome(fetchedToken: nil, hadFetchFailure: false, unresolvedChildIDs: [UUID()]))
        XCTAssertNil(stateManager.serverChangeToken)
        XCTAssertFalse(service.commitPullOutcome(fetchedToken: nil, hadFetchFailure: true, unresolvedChildIDs: []))
        XCTAssertFalse(service.commitPullOutcome(fetchedToken: nil, hadFetchFailure: true, unresolvedChildIDs: [UUID()]))

        // Advances only when the window applied cleanly.
        XCTAssertTrue(service.commitPullOutcome(fetchedToken: nil, hadFetchFailure: false, unresolvedChildIDs: []))
        XCTAssertEqual(stateManager.syncStatus, .synced)
    }

    // MARK: - #1: merge must upload local-newer matched records

    func testReconcileMerge_localNewerRecordsAreUploaded_andLocalPreserved() throws {
        let service = makeService()
        let context = try makeContext()

        let vehicle = makeVehicle(name: "Local Car", createdAt: t1, modifiedAt: t2)
        context.insert(vehicle)
        let record = makeRecord(odometer: 100, createdAt: t1, modifiedAt: t2, vehicle: vehicle)
        context.insert(record)
        try context.save()

        // Older cloud copies of the same records.
        let cloudVehicle = makeVehicle(id: vehicle.id, name: "Old Cloud Car", createdAt: t1, modifiedAt: t1)
        let cloudVehicleCK = service.vehicleToCKRecord(cloudVehicle)
        let cloudRecord = makeRecord(id: record.id, odometer: 999, createdAt: t1, modifiedAt: t1, vehicle: cloudVehicle)
        let cloudRecordCK = service.fuelingRecordToCKRecord(cloudRecord, vehicleRecordID: cloudVehicleCK.recordID)

        let uploads = try service.reconcileMerge(
            vehicleCKRecords: [cloudVehicleCK],
            fuelingCKRecords: [cloudRecordCK],
            context: context
        )

        // The uploaded CKRecords must carry the LOCAL (newer) payload, not just
        // a matching record ID — re-uploading the older cloud copy would pass an
        // ID-only assertion while silently overwriting the newer data.
        let uploadedVehicle = uploads.first { $0.recordID.recordName == vehicle.id.uuidString }
        XCTAssertNotNil(uploadedVehicle, "Local-newer vehicle must be queued for upload")
        XCTAssertEqual(uploadedVehicle?[CloudSyncService.CloudFieldKey.Vehicle.name] as? String, "Local Car")
        XCTAssertEqual(uploadedVehicle?[CloudSyncService.CloudFieldKey.Vehicle.modifiedAt] as? Date, t2)

        let uploadedRecord = uploads.first { $0.recordID.recordName == record.id.uuidString }
        XCTAssertNotNil(uploadedRecord, "Local-newer record must be queued for upload")
        XCTAssertEqual(uploadedRecord?[CloudSyncService.CloudFieldKey.FuelingRecord.odometer] as? Double, 100,
                       "Uploaded record must have the local odometer (100), not the older cloud value (999)")
        XCTAssertEqual(uploadedRecord?[CloudSyncService.CloudFieldKey.FuelingRecord.modifiedAt] as? Date, t2)
        XCTAssertEqual(uploadedRecord?[CloudSyncService.CloudFieldKey.FuelingRecord.vehicleRef] as? String, vehicle.id.uuidString,
                       "Uploaded record must still reference its parent vehicle")

        // Local (newer) values must be preserved, not overwritten by the older cloud copy.
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Vehicle>()).first?.name, "Local Car")
        XCTAssertEqual(try context.fetch(FetchDescriptor<FuelingRecord>()).first?.odometer, 100)
    }

    func testReconcileMerge_cloudNewerUpdatesLocal_andIsNotUploaded() throws {
        let service = makeService()
        let context = try makeContext()

        let vehicle = makeVehicle(name: "Local Car", createdAt: t1, modifiedAt: t1)
        context.insert(vehicle)
        try context.save()

        let cloudVehicle = makeVehicle(id: vehicle.id, name: "Newer Cloud Car", createdAt: t1, modifiedAt: t3)
        let cloudVehicleCK = service.vehicleToCKRecord(cloudVehicle)

        let uploads = try service.reconcileMerge(
            vehicleCKRecords: [cloudVehicleCK],
            fuelingCKRecords: [],
            context: context
        )

        XCTAssertFalse(uploads.contains { $0.recordID.recordName == vehicle.id.uuidString })
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Vehicle>()).first?.name, "Newer Cloud Car")
    }

    func testReconcileMerge_tie_neitherUpdatesNorUploads() throws {
        let service = makeService()
        let context = try makeContext()

        let vehicle = makeVehicle(name: "Local Car", createdAt: t1, modifiedAt: t2)
        context.insert(vehicle)
        try context.save()

        // Identical timestamps → tie → leave both sides untouched.
        let cloudVehicle = makeVehicle(id: vehicle.id, name: "Cloud Car", createdAt: t1, modifiedAt: t2)
        let cloudVehicleCK = service.vehicleToCKRecord(cloudVehicle)

        let uploads = try service.reconcileMerge(
            vehicleCKRecords: [cloudVehicleCK],
            fuelingCKRecords: [],
            context: context
        )

        XCTAssertTrue(uploads.isEmpty, "A tie must not trigger an upload")
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Vehicle>()).first?.name, "Local Car", "A tie must not overwrite local")
    }

    func testReconcileMerge_localOnlyRecordsAreUploaded() throws {
        let service = makeService()
        let context = try makeContext()

        let vehicle = makeVehicle(name: "Only Local", createdAt: t1, modifiedAt: t1)
        context.insert(vehicle)
        try context.save()

        let uploads = try service.reconcileMerge(vehicleCKRecords: [], fuelingCKRecords: [], context: context)
        XCTAssertTrue(uploads.contains { $0.recordID.recordName == vehicle.id.uuidString })
    }

    func testReconcileMerge_cloudOnlyRecordsAreInsertedLocally() throws {
        let service = makeService()
        let context = try makeContext()

        let cloudVehicle = makeVehicle(name: "Cloud Only", createdAt: t1, modifiedAt: t1)
        let cloudVehicleCK = service.vehicleToCKRecord(cloudVehicle)

        let uploads = try service.reconcileMerge(
            vehicleCKRecords: [cloudVehicleCK],
            fuelingCKRecords: [],
            context: context
        )

        XCTAssertFalse(uploads.contains { $0.recordID.recordName == cloudVehicle.id.uuidString })
        try context.save()
        let vehicles = try context.fetch(FetchDescriptor<Vehicle>())
        XCTAssertEqual(vehicles.count, 1)
        XCTAssertEqual(vehicles.first?.name, "Cloud Only")
    }

    // MARK: - Automatic push echo suppression

    func testRemoteApplySaveRemainsSuppressedAfterDebounce() {
        XCTAssertFalse(
            CloudSyncService.shouldScheduleAutomaticPush(
                wasSuppressedWhenSaved: true,
                isCurrentlySuppressed: false
            )
        )
    }

    func testOrdinaryLocalSaveSchedulesAutomaticPush() {
        XCTAssertTrue(
            CloudSyncService.shouldScheduleAutomaticPush(
                wasSuppressedWhenSaved: false,
                isCurrentlySuppressed: false
            )
        )
    }
}
