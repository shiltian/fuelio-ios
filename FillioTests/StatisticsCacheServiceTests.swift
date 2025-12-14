import XCTest
import SwiftData
@testable import Fillio

final class StatisticsCacheServiceTests: XCTestCase {

    // MARK: - Helper Methods

    private func createVehicle(name: String = "Test Car") -> Vehicle {
        return Vehicle(name: name)
    }

    private func createRecord(
        date: Date = Date(),
        currentMiles: Double,
        pricePerGallon: Double = 3.50,
        gallons: Double = 10.0,
        totalCost: Double? = nil,
        fillUpType: FillUpType = .full
    ) -> FuelingRecord {
        let cost = totalCost ?? (pricePerGallon * gallons)
        return FuelingRecord(
            date: date,
            currentMiles: currentMiles,
            pricePerGallon: pricePerGallon,
            gallons: gallons,
            totalCost: cost,
            fillUpType: fillUpType
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

        let record = createRecord(currentMiles: 10000, pricePerGallon: 3.50, gallons: 10.0)
        vehicle.fuelingRecords = [record]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 1)
        XCTAssertEqual(vehicle.cachedTotalSpent, 35.0)
        XCTAssertEqual(vehicle.cachedTotalGallons, 10.0)
        XCTAssertEqual(vehicle.cachedTotalMiles, 0) // No previous record to calculate miles
        XCTAssertEqual(vehicle.cachedAveragePricePerGallon, 3.50)
        XCTAssertNotNil(vehicle.cacheLastUpdated)
    }

    func testRecalculateAllStatisticsWithMultipleRecords() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        let record1 = createRecord(date: date1, currentMiles: 10000, pricePerGallon: 3.00, gallons: 10.0)
        let record2 = createRecord(date: date2, currentMiles: 10300, pricePerGallon: 3.50, gallons: 10.0)
        let record3 = createRecord(date: date3, currentMiles: 10600, pricePerGallon: 4.00, gallons: 10.0)

        vehicle.fuelingRecords = [record1, record2, record3]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 3)
        XCTAssertEqual(vehicle.cachedTotalSpent, 105.0) // 30 + 35 + 40
        XCTAssertEqual(vehicle.cachedTotalGallons, 30.0)
        XCTAssertEqual(vehicle.cachedTotalMiles, 600.0) // 300 + 300
        XCTAssertEqual(vehicle.cachedAveragePricePerGallon!, 3.50, accuracy: 0.001) // (3 + 3.5 + 4) / 3
        XCTAssertEqual(vehicle.cachedAverageFillUpCost, 35.0) // 105 / 3
    }

    func testRecalculateAllStatisticsMPGCalculation() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, currentMiles: 10000, gallons: 10.0)
        let record2 = createRecord(date: date2, currentMiles: 10300, gallons: 10.0) // 300 miles / 10 gallons = 30 MPG

        vehicle.fuelingRecords = [record1, record2]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(vehicle.cachedAverageMPG, 30.0)
        XCTAssertEqual(record2.cachedMPG, 30.0)
        XCTAssertEqual(record2.cachedMilesDriven, 300.0)
        XCTAssertEqual(record2.cachedPreviousMiles, 10000.0)
    }

    func testRecalculateAllStatisticsBestAndWorstMPG() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        let record1 = createRecord(date: date1, currentMiles: 10000, gallons: 10.0)
        let record2 = createRecord(date: date2, currentMiles: 10400, gallons: 10.0) // 40 MPG
        let record3 = createRecord(date: date3, currentMiles: 10600, gallons: 10.0) // 20 MPG

        vehicle.fuelingRecords = [record1, record2, record3]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(vehicle.cachedBestMPG, 40.0)
        XCTAssertEqual(vehicle.cachedWorstMPG, 20.0)
    }

    func testRecalculateAllStatisticsPriceExtremes() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        let record1 = createRecord(date: date1, currentMiles: 10000, pricePerGallon: 3.00, gallons: 10.0)
        let record2 = createRecord(date: date2, currentMiles: 10300, pricePerGallon: 4.50, gallons: 10.0)
        let record3 = createRecord(date: date3, currentMiles: 10600, pricePerGallon: 2.80, gallons: 10.0)

        vehicle.fuelingRecords = [record1, record2, record3]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(vehicle.cachedHighestPricePerGallon, 4.50)
        XCTAssertEqual(vehicle.cachedLowestPricePerGallon, 2.80)
    }

    func testRecalculateAllStatisticsWithPartialFillUp() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        let record1 = createRecord(date: date1, currentMiles: 10000, gallons: 10.0)
        let record2 = createRecord(date: date2, currentMiles: 10300, gallons: 5.0, fillUpType: .partial) // Partial - no MPG
        let record3 = createRecord(date: date3, currentMiles: 10600, gallons: 10.0) // After partial - no MPG

        vehicle.fuelingRecords = [record1, record2, record3]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        // MPG should not be calculated for partial fill-up or the record after it
        XCTAssertNil(record2.cachedMPG)
        XCTAssertNil(record3.cachedMPG)
    }

    func testRecalculateAllStatisticsWithResetFillUp() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        let record1 = createRecord(date: date1, currentMiles: 10000, gallons: 10.0)
        let record2 = createRecord(date: date2, currentMiles: 10300, gallons: 10.0, fillUpType: .reset) // Reset - no MPG
        let record3 = createRecord(date: date3, currentMiles: 10600, gallons: 10.0) // After reset - MPG should be calculated

        vehicle.fuelingRecords = [record1, record2, record3]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        // MPG should not be calculated for reset, but should be for the next one
        XCTAssertNil(record2.cachedMPG)
        // Note: Reset affects its own MPG but the next record can still calculate MPG
    }

    func testRecalculateAllStatisticsCostPerMile() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, currentMiles: 10000, pricePerGallon: 3.50, gallons: 10.0)
        let record2 = createRecord(date: date2, currentMiles: 10350, pricePerGallon: 3.50, gallons: 10.0, totalCost: 35.0)
        // 350 miles, $35 = $0.10/mile

        vehicle.fuelingRecords = [record1, record2]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(record2.cachedCostPerMile!, 0.10, accuracy: 0.001)
        XCTAssertEqual(vehicle.cachedAverageCostPerMile!, 0.20, accuracy: 0.001) // $70 / 350 miles
    }

    // MARK: - Incremental Update Tests

    func testUpdateForNewRecordFirstRecord() {
        let vehicle = createVehicle()
        vehicle.fuelingRecords = []

        let record = createRecord(currentMiles: 10000)
        vehicle.fuelingRecords = [record]

        StatisticsCacheService.updateForNewRecord(record, vehicle: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 1)
        XCTAssertNotNil(vehicle.cacheLastUpdated)
    }

    func testUpdateForNewRecordLatestRecord() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, currentMiles: 10000)
        vehicle.fuelingRecords = [record1]
        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        let record2 = createRecord(date: date2, currentMiles: 10300)
        vehicle.fuelingRecords = [record1, record2]

        StatisticsCacheService.updateForNewRecord(record2, vehicle: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 2)
        XCTAssertEqual(record2.cachedMilesDriven, 300.0)
        XCTAssertEqual(record2.cachedPreviousMiles, 10000.0)
    }

    func testUpdateForNewRecordNotLatest() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        let record1 = createRecord(date: date1, currentMiles: 10000)
        let record3 = createRecord(date: date3, currentMiles: 10600)

        vehicle.fuelingRecords = [record1, record3]
        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        // Insert a record in the middle
        let record2 = createRecord(date: date2, currentMiles: 10300)
        vehicle.fuelingRecords = [record1, record2, record3]

        StatisticsCacheService.updateForNewRecord(record2, vehicle: vehicle)

        // Should trigger full recalculation
        XCTAssertEqual(vehicle.cachedRecordCount, 3)
    }

    // MARK: - Delete and Edit Tests

    func testUpdateForDeletedRecord() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, currentMiles: 10000, pricePerGallon: 3.00, gallons: 10.0)
        let record2 = createRecord(date: date2, currentMiles: 10300, pricePerGallon: 4.00, gallons: 10.0)

        vehicle.fuelingRecords = [record1, record2]
        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        // Simulate deletion
        vehicle.fuelingRecords = [record1]

        StatisticsCacheService.updateForDeletedRecord(vehicle: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 1)
        XCTAssertEqual(vehicle.cachedTotalSpent, 30.0)
        XCTAssertEqual(vehicle.cachedAveragePricePerGallon, 3.00)
    }

    func testUpdateForEditedRecord() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, currentMiles: 10000, pricePerGallon: 3.00, gallons: 10.0)
        let record2 = createRecord(date: date2, currentMiles: 10300, pricePerGallon: 4.00, gallons: 10.0)

        vehicle.fuelingRecords = [record1, record2]
        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        // Edit record2
        record2.pricePerGallon = 5.00
        record2.gallons = 12.0

        StatisticsCacheService.updateForEditedRecord(vehicle: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 2)
        XCTAssertEqual(vehicle.cachedAveragePricePerGallon!, 4.00, accuracy: 0.001) // (3 + 5) / 2
    }

    // MARK: - Cache Validation Tests

    func testEnsureCacheValidWhenCacheIsValid() {
        let vehicle = createVehicle()
        vehicle.fuelingRecords = []
        vehicle.cachedRecordCount = 0
        vehicle.cacheLastUpdated = Date()

        StatisticsCacheService.ensureCacheValid(for: vehicle)

        // Cache should remain unchanged
        XCTAssertEqual(vehicle.cachedRecordCount, 0)
    }

    func testEnsureCacheValidWhenCacheNeedsRebuild() {
        let vehicle = createVehicle()

        let record = createRecord(currentMiles: 10000)
        vehicle.fuelingRecords = [record]

        // No cache set, so it needs rebuild
        XCTAssertNil(vehicle.cacheLastUpdated)

        StatisticsCacheService.ensureCacheValid(for: vehicle)

        XCTAssertEqual(vehicle.cachedRecordCount, 1)
        XCTAssertNotNil(vehicle.cacheLastUpdated)
    }

    func testEnsureCacheValidWhenRecordCountMismatch() {
        let vehicle = createVehicle()

        let record = createRecord(currentMiles: 10000)
        vehicle.fuelingRecords = [record]
        vehicle.cachedRecordCount = 5 // Mismatch!
        vehicle.cacheLastUpdated = Date()

        StatisticsCacheService.ensureCacheValid(for: vehicle)

        // Cache should be rebuilt
        XCTAssertEqual(vehicle.cachedRecordCount, 1)
    }

    // MARK: - Edge Cases

    func testRecalculateWithZeroGallons() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, currentMiles: 10000, gallons: 10.0)
        let record2 = createRecord(date: date2, currentMiles: 10300, gallons: 0) // Zero gallons

        vehicle.fuelingRecords = [record1, record2]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        // Should handle zero gallons gracefully
        XCTAssertNil(record2.cachedMPG) // Can't calculate MPG with zero gallons
    }

    func testRecalculateWithSameMiles() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, currentMiles: 10000, gallons: 10.0)
        let record2 = createRecord(date: date2, currentMiles: 10000, gallons: 10.0) // Same miles

        vehicle.fuelingRecords = [record1, record2]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        // Should handle zero miles driven gracefully
        XCTAssertEqual(record2.cachedMilesDriven, 0)
        XCTAssertNil(record2.cachedMPG) // Can't calculate MPG with zero miles
    }

    func testRecalculateWithRecordsInReverseOrder() {
        let vehicle = createVehicle()

        // Records added in reverse chronological order
        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)
        let date3 = Date(timeIntervalSince1970: 3000000)

        let record1 = createRecord(date: date1, currentMiles: 10000, gallons: 10.0)
        let record2 = createRecord(date: date2, currentMiles: 10300, gallons: 10.0)
        let record3 = createRecord(date: date3, currentMiles: 10600, gallons: 10.0)

        // Add in reverse order
        vehicle.fuelingRecords = [record3, record1, record2]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        // Should still calculate correctly after sorting
        XCTAssertEqual(vehicle.cachedTotalMiles, 600.0)
        XCTAssertEqual(vehicle.cachedRecordCount, 3)
    }

    func testMPGCalculationAccuracy() {
        let vehicle = createVehicle()

        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let record1 = createRecord(date: date1, currentMiles: 10000, gallons: 10.0)
        let record2 = createRecord(date: date2, currentMiles: 10333, gallons: 11.1) // 333 miles / 11.1 gallons = 30.0 MPG

        vehicle.fuelingRecords = [record1, record2]

        StatisticsCacheService.recalculateAllStatistics(for: vehicle)

        XCTAssertEqual(record2.cachedMPG!, 30.0, accuracy: 0.01)
    }
}

