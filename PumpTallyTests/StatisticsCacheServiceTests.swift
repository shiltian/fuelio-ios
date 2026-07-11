import XCTest
import SwiftData
@testable import PumpTally

final class StatisticsCacheServiceTests: XCTestCase {

    // MARK: - Helper Methods

    private func createVehicle(name: String = "Test Car") -> Vehicle {
        return Vehicle(name: name)
    }

    private func createRecord(
        date: Date = Date(),
        odometer: Double,
        pricePerFuelUnit: Double = 3.50,
        fuelAmount: Double = 10.0,
        totalCost: Double? = nil,
        fillUpType: FillUpType = .full,
        vehicle: Vehicle? = nil
    ) -> FuelingRecord {
        let cost = totalCost ?? (pricePerFuelUnit * fuelAmount)
        let v = vehicle ?? Vehicle(name: "Helper Vehicle")
        return FuelingRecord(
            date: date,
            odometer: odometer,
            pricePerFuelUnit: pricePerFuelUnit,
            fuelAmount: fuelAmount,
            totalCost: cost,
            fillUpType: fillUpType,
            vehicle: v
        )
    }

    // MARK: - Recalculate All Statistics Tests

    func testRecalculateAllStatisticsWithNoRecords() {
        let vehicle = createVehicle()
        vehicle.fuelingRecords = []

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 0)
        XCTAssertNotNil(vehicle.cacheLastUpdated)
    }

    func testRecalculateAllStatisticsWithSingleRecord() {
        let vehicle = createVehicle()

        let record = createRecord(odometer: 10000, pricePerFuelUnit: 3.50, fuelAmount: 10.0, vehicle: vehicle)
        vehicle.fuelingRecords = [record]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 1)
        XCTAssertEqual(vehicle.cachedTotalSpent, 35.0)
        XCTAssertEqual(vehicle.cachedTotalFuel, 10.0)
        XCTAssertEqual(vehicle.cachedTotalDistance, 0) // No previous record to calculate distance
        XCTAssertEqual(vehicle.cachedAveragePricePerFuelUnit, 3.50)
        XCTAssertNotNil(vehicle.cacheLastUpdated)
    }

    func testRecalculateAllStatisticsWithMultipleRecords() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        let record1 = createRecord(date: date1, odometer: 10000, pricePerFuelUnit: 3.00, fuelAmount: 10.0, vehicle: vehicle)
        let record2 = createRecord(date: date2, odometer: 10300, pricePerFuelUnit: 3.50, fuelAmount: 10.0, vehicle: vehicle)
        let record3 = createRecord(date: date3, odometer: 10600, pricePerFuelUnit: 4.00, fuelAmount: 10.0, vehicle: vehicle)

        vehicle.fuelingRecords = [record1, record2, record3]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 3)
        XCTAssertEqual(vehicle.cachedTotalSpent, 105.0) // 30 + 35 + 40
        XCTAssertEqual(vehicle.cachedTotalFuel, 30.0)
        XCTAssertEqual(vehicle.cachedTotalDistance, 600.0) // 300 + 300
        XCTAssertEqual(vehicle.cachedAveragePricePerFuelUnit!, 3.50, accuracy: 0.001) // (3 + 3.5 + 4) / 3
        XCTAssertEqual(vehicle.cachedAverageFillUpCost, 35.0) // 105 / 3
    }

    func testRecalculateAllStatisticsEfficiencyCalculation() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, odometer: 10000, fuelAmount: 10.0, vehicle: vehicle)
        let record2 = createRecord(date: date2, odometer: 10300, fuelAmount: 10.0, vehicle: vehicle) // 300 / 10 = 30

        vehicle.fuelingRecords = [record1, record2]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(vehicle.cachedAverageEfficiency, 30.0)
        XCTAssertEqual(record2.cachedEfficiency, 30.0)
        XCTAssertEqual(record2.cachedDistanceDriven, 300.0)
        XCTAssertEqual(record2.cachedPreviousOdometer, 10000.0)
    }

    func testRecalculateAllStatisticsBestAndWorstEfficiency() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        let record1 = createRecord(date: date1, odometer: 10000, fuelAmount: 10.0, vehicle: vehicle)
        let record2 = createRecord(date: date2, odometer: 10400, fuelAmount: 10.0, vehicle: vehicle) // 40
        let record3 = createRecord(date: date3, odometer: 10600, fuelAmount: 10.0, vehicle: vehicle) // 20

        vehicle.fuelingRecords = [record1, record2, record3]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(vehicle.cachedBestEfficiency, 40.0)
        XCTAssertEqual(vehicle.cachedWorstEfficiency, 20.0)
    }

    func testRecalculateAllStatisticsPriceExtremes() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        let record1 = createRecord(date: date1, odometer: 10000, pricePerFuelUnit: 3.00, fuelAmount: 10.0, vehicle: vehicle)
        let record2 = createRecord(date: date2, odometer: 10300, pricePerFuelUnit: 4.50, fuelAmount: 10.0, vehicle: vehicle)
        let record3 = createRecord(date: date3, odometer: 10600, pricePerFuelUnit: 2.80, fuelAmount: 10.0, vehicle: vehicle)

        vehicle.fuelingRecords = [record1, record2, record3]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(vehicle.cachedHighestPricePerFuelUnit, 4.50)
        XCTAssertEqual(vehicle.cachedLowestPricePerFuelUnit, 2.80)
    }

    func testRecalculateAllStatisticsWithPartialFillUp() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        let record1 = createRecord(date: date1, odometer: 10000, fuelAmount: 10.0, vehicle: vehicle)
        let record2 = createRecord(date: date2, odometer: 10300, fuelAmount: 5.0, fillUpType: .partial, vehicle: vehicle)
        let record3 = createRecord(date: date3, odometer: 10600, fuelAmount: 10.0, vehicle: vehicle)

        vehicle.fuelingRecords = [record1, record2, record3]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertNil(record2.cachedEfficiency)
        XCTAssertNil(record3.cachedEfficiency)
    }

    func testRecalculateAllStatisticsWithResetFillUp() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        let record1 = createRecord(date: date1, odometer: 10000, fuelAmount: 10.0, vehicle: vehicle)
        let record2 = createRecord(date: date2, odometer: 10300, fuelAmount: 10.0, fillUpType: .reset, vehicle: vehicle)
        let record3 = createRecord(date: date3, odometer: 10600, fuelAmount: 10.0, vehicle: vehicle)

        vehicle.fuelingRecords = [record1, record2, record3]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertNil(record2.cachedEfficiency)
    }

    func testRecalculateAllStatisticsCostPerDistance() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, odometer: 10000, pricePerFuelUnit: 3.50, fuelAmount: 10.0, vehicle: vehicle)
        let record2 = createRecord(date: date2, odometer: 10350, pricePerFuelUnit: 3.50, fuelAmount: 10.0, totalCost: 35.0, vehicle: vehicle)

        vehicle.fuelingRecords = [record1, record2]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(record2.cachedCostPerDistance!, 0.10, accuracy: 0.001)
        XCTAssertEqual(vehicle.cachedAverageCostPerDistance!, 0.20, accuracy: 0.001) // $70 / 350
    }

    // MARK: - Incremental Update Tests

    func testUpdateForNewRecordFirstRecord() {
        let vehicle = createVehicle()
        vehicle.fuelingRecords = []

        let record = createRecord(odometer: 10000, vehicle: vehicle)
        vehicle.fuelingRecords = [record]

        StatisticsCacheService.updateForNewRecord(record, vehicle: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 1)
        XCTAssertNotNil(vehicle.cacheLastUpdated)
    }

    func testUpdateForNewRecordLatestRecord() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, odometer: 10000, vehicle: vehicle)
        vehicle.fuelingRecords = [record1]
        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        let record2 = createRecord(date: date2, odometer: 10300, vehicle: vehicle)
        vehicle.fuelingRecords = [record1, record2]

        StatisticsCacheService.updateForNewRecord(record2, vehicle: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 2)
        XCTAssertEqual(record2.cachedDistanceDriven, 300.0)
        XCTAssertEqual(record2.cachedPreviousOdometer, 10000.0)
    }

    func testUpdateForNewRecordLatestRecordUpdatesAverageEfficiency() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        let record1 = createRecord(date: date1, odometer: 10000, fuelAmount: 10.0, vehicle: vehicle)
        let record2 = createRecord(date: date2, odometer: 10300, fuelAmount: 10.0, vehicle: vehicle)
        vehicle.fuelingRecords = [record1, record2]
        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(vehicle.cachedAverageEfficiency, 30.0) // 300 / 10

        let record3 = createRecord(date: date3, odometer: 10500, fuelAmount: 10.0, vehicle: vehicle)
        vehicle.fuelingRecords = [record1, record2, record3]

        StatisticsCacheService.updateForNewRecord(record3, vehicle: vehicle)

        // After incremental add: fullFillUpDistance = 300 + 200 = 500,
        // fullFillUpFuel = 10 (record2) + 10 (record3) = 20
        // (baseline record1's fuel is excluded — it has no valid efficiency)
        XCTAssertNotNil(vehicle.cachedAverageEfficiency)
        XCTAssertEqual(vehicle.cachedAverageEfficiency!, 500.0 / 20.0, accuracy: 0.001)
    }

    func testUpdateForNewRecordAfterPartialExcludesInvalidEfficiency() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        // record1: full (baseline), record2: partial (breaks efficiency chain)
        let record1 = createRecord(date: date1, odometer: 10000, fuelAmount: 10.0, vehicle: vehicle)
        let record2 = createRecord(date: date2, odometer: 10300, fuelAmount: 5.0, fillUpType: .partial, vehicle: vehicle)
        vehicle.fuelingRecords = [record1, record2]
        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        // Partial after full → no valid efficiency intervals yet
        XCTAssertNil(record2.cachedEfficiency)

        // record3: full latest, but previous was partial → no efficiency for record3
        let record3 = createRecord(date: date3, odometer: 10600, fuelAmount: 10.0, vehicle: vehicle)
        vehicle.fuelingRecords = [record1, record2, record3]

        StatisticsCacheService.updateForNewRecord(record3, vehicle: vehicle)

        // record3 should have no efficiency (previous was partial)
        XCTAssertNil(record3.cachedEfficiency)

        // No valid full-to-full intervals exist, so cachedAverageEfficiency
        // should use the fallback (totalDistance / totalFuel), matching full recalc
        let expectedTotalDistance = 300.0 + 300.0  // 600
        let expectedTotalFuel = 10.0 + 5.0 + 10.0 // 25
        XCTAssertEqual(vehicle.cachedAverageEfficiency!, expectedTotalDistance / expectedTotalFuel, accuracy: 0.001)

        // Verify incremental result matches a full recalculation
        let incrementalAvg = vehicle.cachedAverageEfficiency!
        StatisticsCacheService.recalculateAllStatistics(for: vehicle)
        XCTAssertEqual(vehicle.cachedAverageEfficiency!, incrementalAvg, accuracy: 0.001)
    }

    func testUpdateForNewRecordNotLatest() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        let record1 = createRecord(date: date1, odometer: 10000, vehicle: vehicle)
        let record3 = createRecord(date: date3, odometer: 10600, vehicle: vehicle)

        vehicle.fuelingRecords = [record1, record3]
        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        let record2 = createRecord(date: date2, odometer: 10300, vehicle: vehicle)
        vehicle.fuelingRecords = [record1, record2, record3]

        StatisticsCacheService.updateForNewRecord(record2, vehicle: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 3)
    }

    // MARK: - Delete and Edit Tests

    func testUpdateForDeletedRecord() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, odometer: 10000, pricePerFuelUnit: 3.00, fuelAmount: 10.0, vehicle: vehicle)
        let record2 = createRecord(date: date2, odometer: 10300, pricePerFuelUnit: 4.00, fuelAmount: 10.0, vehicle: vehicle)

        vehicle.fuelingRecords = [record1, record2]
        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        vehicle.fuelingRecords = [record1]
        StatisticsCacheService.updateForDeletedRecord(vehicle: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 1)
        XCTAssertEqual(vehicle.cachedTotalSpent, 30.0)
        XCTAssertEqual(vehicle.cachedAveragePricePerFuelUnit, 3.00)
    }

    func testUpdateForEditedRecord() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, odometer: 10000, pricePerFuelUnit: 3.00, fuelAmount: 10.0, vehicle: vehicle)
        let record2 = createRecord(date: date2, odometer: 10300, pricePerFuelUnit: 4.00, fuelAmount: 10.0, vehicle: vehicle)

        vehicle.fuelingRecords = [record1, record2]
        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        record2.pricePerFuelUnit = 5.00
        record2.fuelAmount = 12.0

        StatisticsCacheService.updateForEditedRecord(vehicle: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 2)
        XCTAssertEqual(vehicle.cachedAveragePricePerFuelUnit!, 4.00, accuracy: 0.001) // (3 + 5) / 2
    }

    // MARK: - Cache Validation Tests

    func testEnsureCacheValidWhenCacheIsValid() {
        let vehicle = createVehicle()
        vehicle.fuelingRecords = []
        vehicle.cachedRecordCount = 0
        vehicle.cacheLastUpdated = Date()

        StatisticsCacheService.ensureCacheValid(for: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 0)
    }

    func testEnsureCacheValidWhenCacheNeedsRebuild() {
        let vehicle = createVehicle()

        let record = createRecord(odometer: 10000, vehicle: vehicle)
        vehicle.fuelingRecords = [record]

        XCTAssertNil(vehicle.cacheLastUpdated)

        StatisticsCacheService.ensureCacheValid(for: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 1)
        XCTAssertNotNil(vehicle.cacheLastUpdated)
    }

    func testEnsureCacheValidWhenRecordCountMismatch() {
        let vehicle = createVehicle()

        let record = createRecord(odometer: 10000, vehicle: vehicle)
        vehicle.fuelingRecords = [record]
        vehicle.cachedRecordCount = 5

        StatisticsCacheService.ensureCacheValid(for: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 1)
    }

    // MARK: - Edge Cases

    func testRecalculateWithZeroFuelAmount() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, odometer: 10000, fuelAmount: 10.0, vehicle: vehicle)
        let record2 = createRecord(date: date2, odometer: 10300, fuelAmount: 0, vehicle: vehicle)

        vehicle.fuelingRecords = [record1, record2]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertNil(record2.cachedEfficiency)
    }

    func testRecalculateWithSameOdometer() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, odometer: 10000, fuelAmount: 10.0, vehicle: vehicle)
        let record2 = createRecord(date: date2, odometer: 10000, fuelAmount: 10.0, vehicle: vehicle)

        vehicle.fuelingRecords = [record1, record2]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(record2.cachedDistanceDriven, 0)
        XCTAssertNil(record2.cachedEfficiency)
    }

    func testRecalculateWithRecordsInReverseOrder() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        let record1 = createRecord(date: date1, odometer: 10000, fuelAmount: 10.0, vehicle: vehicle)
        let record2 = createRecord(date: date2, odometer: 10300, fuelAmount: 10.0, vehicle: vehicle)
        let record3 = createRecord(date: date3, odometer: 10600, fuelAmount: 10.0, vehicle: vehicle)

        vehicle.fuelingRecords = [record3, record1, record2]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(vehicle.cachedTotalDistance, 600.0)
        XCTAssertEqual(vehicle.cachedRecordCount, 3)
    }

    func testEfficiencyCalculationAccuracy() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, odometer: 10000, fuelAmount: 10.0, vehicle: vehicle)
        let record2 = createRecord(date: date2, odometer: 10333, fuelAmount: 11.1, vehicle: vehicle) // 333 / 11.1 = 30.0

        vehicle.fuelingRecords = [record1, record2]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(record2.cachedEfficiency!, 30.0, accuracy: 0.01)
    }
}
