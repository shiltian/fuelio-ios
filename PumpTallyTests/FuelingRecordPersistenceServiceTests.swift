import XCTest
import SwiftData
@testable import PumpTally

@MainActor
final class FuelingRecordPersistenceServiceTests: XCTestCase {

    private enum TestError: Error {
        case commitFailed
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeSavedVehicle(in context: ModelContext) throws -> Vehicle {
        let vehicle = Vehicle(name: "Test Car")
        context.insert(vehicle)
        try context.save()
        return vehicle
    }

    private func insertRecord(
        odometer: Double = 100,
        into vehicle: Vehicle,
        context: ModelContext
    ) throws -> FuelingRecord {
        try FuelingRecordPersistenceService.insert(into: vehicle, context: context) {
            FuelingRecord(
                odometer: odometer,
                pricePerFuelUnit: 3,
                fuelAmount: 10,
                totalCost: 30,
                vehicle: vehicle
            )
        }
    }

    func testInsertProcessesInverseRelationshipAndCommitsCachesOnce() throws {
        let context = try makeContext()
        let vehicle = try makeSavedVehicle(in: context)
        var commitCount = 0

        let record = try FuelingRecordPersistenceService.insert(
            into: vehicle,
            context: context,
            commit: {
                commitCount += 1
                try $0.save()
            }
        ) {
            FuelingRecord(
                odometer: 100,
                pricePerFuelUnit: 3,
                fuelAmount: 10,
                totalCost: 30,
                vehicle: vehicle
            )
        }

        XCTAssertEqual(commitCount, 1)
        XCTAssertEqual(vehicle.fuelingRecords?.map(\.id), [record.id])
        XCTAssertEqual(vehicle.cachedRecordCount, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FuelingRecord>()), 1)
        XCTAssertFalse(context.hasChanges)
    }

    func testDeleteProcessesInverseRelationshipBeforeCacheRecalculation() throws {
        let context = try makeContext()
        let vehicle = try makeSavedVehicle(in: context)
        let record = try insertRecord(into: vehicle, context: context)

        try FuelingRecordPersistenceService.delete(record, from: vehicle, context: context)

        XCTAssertTrue((vehicle.fuelingRecords ?? []).isEmpty)
        XCTAssertEqual(vehicle.cachedRecordCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FuelingRecord>()), 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testEditCommitsRecordAndCacheChangesTogether() throws {
        let context = try makeContext()
        let vehicle = try makeSavedVehicle(in: context)
        let first = try insertRecord(odometer: 100, into: vehicle, context: context)
        let second = try insertRecord(odometer: 200, into: vehicle, context: context)

        try FuelingRecordPersistenceService.saveEdits(
            to: second,
            in: vehicle,
            context: context
        ) {
            second.odometer = 250
            second.totalCost = 45
        }

        XCTAssertEqual(first.cachedDistanceDriven, 0)
        XCTAssertEqual(second.odometer, 250)
        XCTAssertEqual(second.cachedDistanceDriven, 150)
        XCTAssertEqual(vehicle.cachedTotalSpent, 75)
        XCTAssertFalse(context.hasChanges)
    }

    func testFailedInsertRollsBackRecordAndCaches() throws {
        let context = try makeContext()
        let vehicle = try makeSavedVehicle(in: context)

        XCTAssertThrowsError(
            try FuelingRecordPersistenceService.insert(
                into: vehicle,
                context: context,
                commit: { _ in throw TestError.commitFailed }
            ) {
                FuelingRecord(
                    odometer: 100,
                    pricePerFuelUnit: 3,
                    fuelAmount: 10,
                    totalCost: 30,
                    vehicle: vehicle
                )
            }
        )

        XCTAssertTrue((vehicle.fuelingRecords ?? []).isEmpty)
        XCTAssertNil(vehicle.cachedRecordCount)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FuelingRecord>()), 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testBatchInsertCommitsEveryRecordAndCachesOnce() throws {
        let context = try makeContext()
        let vehicle = try makeSavedVehicle(in: context)
        var commitCount = 0

        let records = try FuelingRecordPersistenceService.insertBatch(
            into: vehicle,
            context: context,
            commit: {
                commitCount += 1
                try $0.save()
            }
        ) {
            [100.0, 200.0, 300.0].map { odometer in
                FuelingRecord(
                    odometer: odometer,
                    pricePerFuelUnit: 3,
                    fuelAmount: 10,
                    totalCost: 30,
                    vehicle: vehicle
                )
            }
        }

        XCTAssertEqual(commitCount, 1)
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(vehicle.fuelingRecords?.count, 3)
        XCTAssertEqual(vehicle.cachedRecordCount, 3)
        XCTAssertEqual(vehicle.cachedTotalDistance, 200)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FuelingRecord>()), 3)
        XCTAssertFalse(context.hasChanges)
    }

    func testFailedBatchInsertRollsBackEveryRecordAndCache() throws {
        let context = try makeContext()
        let vehicle = try makeSavedVehicle(in: context)
        _ = try insertRecord(odometer: 50, into: vehicle, context: context)
        let originalRecordCount = vehicle.cachedRecordCount
        let originalDistance = vehicle.cachedTotalDistance

        XCTAssertThrowsError(
            try FuelingRecordPersistenceService.insertBatch(
                into: vehicle,
                context: context,
                commit: { _ in throw TestError.commitFailed }
            ) {
                [100.0, 200.0, 300.0].map { odometer in
                    FuelingRecord(
                        odometer: odometer,
                        pricePerFuelUnit: 3,
                        fuelAmount: 10,
                        totalCost: 30,
                        vehicle: vehicle
                    )
                }
            }
        )

        XCTAssertEqual(vehicle.fuelingRecords?.map(\.odometer), [50])
        XCTAssertEqual(vehicle.cachedRecordCount, originalRecordCount)
        XCTAssertEqual(vehicle.cachedTotalDistance, originalDistance)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FuelingRecord>()), 1)
        XCTAssertFalse(context.hasChanges)
    }

    func testFailedEditRollsBackRecordAndCaches() throws {
        let context = try makeContext()
        let vehicle = try makeSavedVehicle(in: context)
        let first = try insertRecord(odometer: 100, into: vehicle, context: context)
        let second = try insertRecord(odometer: 200, into: vehicle, context: context)
        let originalTotalDistance = vehicle.cachedTotalDistance

        XCTAssertThrowsError(
            try FuelingRecordPersistenceService.saveEdits(
                to: second,
                in: vehicle,
                context: context,
                commit: { _ in throw TestError.commitFailed }
            ) {
                second.odometer = 300
                second.totalCost = 99
            }
        )

        XCTAssertEqual(first.cachedDistanceDriven, 0)
        XCTAssertEqual(second.odometer, 200)
        XCTAssertEqual(second.totalCost, 30)
        XCTAssertEqual(vehicle.cachedTotalDistance, originalTotalDistance)
        XCTAssertFalse(context.hasChanges)
    }

    func testFailedDeleteRestoresRecordAndCaches() throws {
        let context = try makeContext()
        let vehicle = try makeSavedVehicle(in: context)
        let record = try insertRecord(into: vehicle, context: context)

        XCTAssertThrowsError(
            try FuelingRecordPersistenceService.delete(
                record,
                from: vehicle,
                context: context,
                commit: { _ in throw TestError.commitFailed }
            )
        )

        XCTAssertEqual(vehicle.fuelingRecords?.map(\.id), [record.id])
        XCTAssertEqual(vehicle.cachedRecordCount, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FuelingRecord>()), 1)
        XCTAssertFalse(context.hasChanges)
    }
}
