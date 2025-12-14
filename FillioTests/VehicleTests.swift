import XCTest
import SwiftData
@testable import Fillio

final class VehicleTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitializationWithDefaultValues() {
        let vehicle = Vehicle(name: "My Car")

        XCTAssertEqual(vehicle.name, "My Car")
        XCTAssertNil(vehicle.make)
        XCTAssertNil(vehicle.model)
        XCTAssertNil(vehicle.year)
        XCTAssertNotNil(vehicle.id)
        XCTAssertNotNil(vehicle.createdAt)
    }

    func testInitializationWithAllValues() {
        let customId = UUID()
        let customDate = Date(timeIntervalSince1970: 1000000)

        let vehicle = Vehicle(
            id: customId,
            name: "Daily Driver",
            make: "Toyota",
            model: "Camry",
            year: 2023,
            createdAt: customDate
        )

        XCTAssertEqual(vehicle.id, customId)
        XCTAssertEqual(vehicle.name, "Daily Driver")
        XCTAssertEqual(vehicle.make, "Toyota")
        XCTAssertEqual(vehicle.model, "Camry")
        XCTAssertEqual(vehicle.year, 2023)
        XCTAssertEqual(vehicle.createdAt, customDate)
    }

    // MARK: - Display Name Tests

    func testDisplayNameWithMakeModelAndYear() {
        let vehicle = Vehicle(
            name: "My Car",
            make: "Honda",
            model: "Accord",
            year: 2022
        )

        XCTAssertEqual(vehicle.displayName, "2022 Honda Accord")
    }

    func testDisplayNameWithMakeAndModelOnly() {
        let vehicle = Vehicle(
            name: "My Car",
            make: "Honda",
            model: "Accord",
            year: nil
        )

        XCTAssertEqual(vehicle.displayName, "Honda Accord")
    }

    func testDisplayNameWithNameOnly() {
        let vehicle = Vehicle(name: "Family Van")

        XCTAssertEqual(vehicle.displayName, "Family Van")
    }

    func testDisplayNameWithMakeOnlyFallsBackToName() {
        let vehicle = Vehicle(
            name: "My Car",
            make: "Honda",
            model: nil,
            year: nil
        )

        XCTAssertEqual(vehicle.displayName, "My Car")
    }

    func testDisplayNameWithModelOnlyFallsBackToName() {
        let vehicle = Vehicle(
            name: "My Car",
            make: nil,
            model: "Accord",
            year: nil
        )

        XCTAssertEqual(vehicle.displayName, "My Car")
    }

    // MARK: - Sorted Records Tests

    func testSortedRecordsEmptyWhenNoRecords() {
        let vehicle = Vehicle(name: "Test Car")

        XCTAssertTrue(vehicle.sortedRecords.isEmpty)
    }

    func testSortedRecordsReturnsMostRecentFirst() {
        let vehicle = Vehicle(name: "Test Car")

        let oldDate = Date(timeIntervalSince1970: 1000000)
        let newDate = Date(timeIntervalSince1970: 2000000)

        let oldRecord = FuelingRecord(
            date: oldDate,
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0
        )

        let newRecord = FuelingRecord(
            date: newDate,
            currentMiles: 10500,
            pricePerGallon: 3.60,
            gallons: 11.0,
            totalCost: 39.60
        )

        vehicle.fuelingRecords = [oldRecord, newRecord]

        let sorted = vehicle.sortedRecords
        XCTAssertEqual(sorted.count, 2)
        XCTAssertEqual(sorted[0].date, newDate)
        XCTAssertEqual(sorted[1].date, oldDate)
    }

    // MARK: - Last Record Tests

    func testLastRecordReturnsNilWhenNoRecords() {
        let vehicle = Vehicle(name: "Test Car")

        XCTAssertNil(vehicle.lastRecord)
    }

    func testLastRecordReturnsMostRecentRecord() {
        let vehicle = Vehicle(name: "Test Car")

        let oldDate = Date(timeIntervalSince1970: 1000000)
        let newDate = Date(timeIntervalSince1970: 2000000)

        let oldRecord = FuelingRecord(
            date: oldDate,
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0
        )

        let newRecord = FuelingRecord(
            date: newDate,
            currentMiles: 10500,
            pricePerGallon: 3.60,
            gallons: 11.0,
            totalCost: 39.60
        )

        vehicle.fuelingRecords = [oldRecord, newRecord]

        let lastRecord = vehicle.lastRecord
        XCTAssertNotNil(lastRecord)
        XCTAssertEqual(lastRecord?.date, newDate)
        XCTAssertEqual(lastRecord?.currentMiles, 10500)
    }

    // MARK: - Cache Status Tests

    func testNeedsCacheRebuildWhenNoCacheExists() {
        let vehicle = Vehicle(name: "Test Car")

        XCTAssertTrue(vehicle.needsCacheRebuild)
    }

    func testNeedsCacheRebuildWhenCacheCountMismatch() {
        let vehicle = Vehicle(name: "Test Car")

        vehicle.cacheLastUpdated = Date()
        vehicle.cachedRecordCount = 5

        // No records but cache says 5
        XCTAssertTrue(vehicle.needsCacheRebuild)
    }

    func testNeedsCacheRebuildFalseWhenCacheMatches() {
        let vehicle = Vehicle(name: "Test Car")

        vehicle.cacheLastUpdated = Date()
        vehicle.cachedRecordCount = 0

        XCTAssertFalse(vehicle.needsCacheRebuild)
    }

    func testNeedsCacheRebuildWhenRecordCountIsNil() {
        let vehicle = Vehicle(name: "Test Car")

        vehicle.cacheLastUpdated = Date()
        vehicle.cachedRecordCount = nil

        XCTAssertTrue(vehicle.needsCacheRebuild)
    }

    // MARK: - Invalidate Cache Tests

    func testInvalidateCacheClearsAllCachedValues() {
        let vehicle = Vehicle(name: "Test Car")

        // Set all cached values
        vehicle.cachedTotalSpent = 1000.0
        vehicle.cachedTotalMiles = 5000.0
        vehicle.cachedTotalGallons = 200.0
        vehicle.cachedAverageMPG = 25.0
        vehicle.cachedAverageCostPerMile = 0.20
        vehicle.cachedAverageFillUpCost = 50.0
        vehicle.cachedAveragePricePerGallon = 3.50
        vehicle.cachedBestMPG = 32.0
        vehicle.cachedWorstMPG = 18.0
        vehicle.cachedHighestPricePerGallon = 4.50
        vehicle.cachedLowestPricePerGallon = 2.80
        vehicle.cachedRecordCount = 20
        vehicle.cacheLastUpdated = Date()

        // Invalidate cache
        vehicle.invalidateCache()

        // Verify all values are nil
        XCTAssertNil(vehicle.cachedTotalSpent)
        XCTAssertNil(vehicle.cachedTotalMiles)
        XCTAssertNil(vehicle.cachedTotalGallons)
        XCTAssertNil(vehicle.cachedAverageMPG)
        XCTAssertNil(vehicle.cachedAverageCostPerMile)
        XCTAssertNil(vehicle.cachedAverageFillUpCost)
        XCTAssertNil(vehicle.cachedAveragePricePerGallon)
        XCTAssertNil(vehicle.cachedBestMPG)
        XCTAssertNil(vehicle.cachedWorstMPG)
        XCTAssertNil(vehicle.cachedHighestPricePerGallon)
        XCTAssertNil(vehicle.cachedLowestPricePerGallon)
        XCTAssertNil(vehicle.cachedRecordCount)
        XCTAssertNil(vehicle.cacheLastUpdated)
    }

    // MARK: - Edge Cases

    func testVehicleWithEmptyName() {
        let vehicle = Vehicle(name: "")

        XCTAssertEqual(vehicle.name, "")
        XCTAssertEqual(vehicle.displayName, "")
    }

    func testVehicleWithZeroYear() {
        let vehicle = Vehicle(
            name: "Test Car",
            make: "Toyota",
            model: "Corolla",
            year: 0
        )

        // Year 0 should still be included
        XCTAssertEqual(vehicle.displayName, "0 Toyota Corolla")
    }

    func testVehicleWithNegativeYear() {
        let vehicle = Vehicle(
            name: "Test Car",
            make: "Toyota",
            model: "Corolla",
            year: -1
        )

        XCTAssertEqual(vehicle.displayName, "-1 Toyota Corolla")
    }
}

