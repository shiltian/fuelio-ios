import XCTest
import SwiftData
@testable import PumpTally

final class FuelingRecordTests: XCTestCase {
    private let testVehicle = Vehicle(name: "Test Car")

    // MARK: - Initialization Tests

    func testInitializationWithDefaultValues() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 12.5,
            totalCost: 43.75,
            vehicle: testVehicle
        )

        XCTAssertEqual(record.odometer, 10000)
        XCTAssertEqual(record.pricePerFuelUnit, 3.50)
        XCTAssertEqual(record.fuelAmount, 12.5)
        XCTAssertEqual(record.totalCost, 43.75)
        XCTAssertEqual(record.fillUpType, .full)
        XCTAssertNil(record.notes)
        XCTAssertNotNil(record.id)
        XCTAssertNotNil(record.date)
        XCTAssertNotNil(record.createdAt)
    }

    func testInitializationWithCustomValues() {
        let customId = UUID()
        let customDate = Date(timeIntervalSince1970: 1000000)

        let record = FuelingRecord(
            id: customId,
            date: customDate,
            odometer: 25000,
            pricePerFuelUnit: 4.25,
            fuelAmount: 15.0,
            totalCost: 63.75,
            fillUpType: .partial,
            notes: "Test note",
            createdAt: customDate,
            vehicle: testVehicle
        )

        XCTAssertEqual(record.id, customId)
        XCTAssertEqual(record.date, customDate)
        XCTAssertEqual(record.odometer, 25000)
        XCTAssertEqual(record.pricePerFuelUnit, 4.25)
        XCTAssertEqual(record.fuelAmount, 15.0)
        XCTAssertEqual(record.totalCost, 63.75)
        XCTAssertEqual(record.fillUpType, .partial)
        XCTAssertEqual(record.notes, "Test note")
    }

    // MARK: - Fill-up Type Tests

    func testFillUpTypeAccessor() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 12.5,
            totalCost: 43.75,
            fillUpType: .full,
            vehicle: testVehicle
        )

        XCTAssertEqual(record.fillUpType, .full)
        XCTAssertEqual(record.fillUpTypeRaw, "full")

        record.fillUpType = .partial
        XCTAssertEqual(record.fillUpType, .partial)
        XCTAssertEqual(record.fillUpTypeRaw, "partial")

        record.fillUpType = .reset
        XCTAssertEqual(record.fillUpType, .reset)
        XCTAssertEqual(record.fillUpTypeRaw, "reset")
    }

    func testIsPartialFillUp() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 12.5,
            totalCost: 43.75,
            fillUpType: .partial,
            vehicle: testVehicle
        )

        XCTAssertTrue(record.isPartialFillUp)
        XCTAssertFalse(record.isFullFillUp)
    }

    func testIsReset() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 12.5,
            totalCost: 43.75,
            fillUpType: .reset,
            vehicle: testVehicle
        )

        XCTAssertEqual(record.fillUpType, .reset)
        XCTAssertFalse(record.isFullFillUp)
        XCTAssertFalse(record.isPartialFillUp)
    }

    func testIsFullFillUp() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 12.5,
            totalCost: 43.75,
            fillUpType: .full,
            vehicle: testVehicle
        )

        XCTAssertTrue(record.isFullFillUp)
        XCTAssertFalse(record.isPartialFillUp)
    }

    // MARK: - Cached Value Tests

    func testGetPreviousOdometerWithCachedValue() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 12.5,
            totalCost: 43.75,
            vehicle: testVehicle
        )

        record.cachedPreviousOdometer = 9500
        XCTAssertEqual(record.getPreviousOdometer(), 9500)
    }

    func testGetPreviousOdometerWithFallback() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 12.5,
            totalCost: 43.75,
            vehicle: testVehicle
        )

        XCTAssertEqual(record.getPreviousOdometer(fallback: 100), 100)
    }

    func testGetDistanceDrivenWithCachedValue() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 12.5,
            totalCost: 43.75,
            vehicle: testVehicle
        )

        record.cachedDistanceDriven = 500
        XCTAssertEqual(record.getDistanceDriven(), 500)
    }

    func testGetDistanceDrivenCalculated() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 12.5,
            totalCost: 43.75,
            vehicle: testVehicle
        )

        record.cachedPreviousOdometer = 9500
        XCTAssertEqual(record.getDistanceDriven(), 500)
    }

    func testGetDistanceDrivenNoPreviousOdometer() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 12.5,
            totalCost: 43.75,
            vehicle: testVehicle
        )

        XCTAssertEqual(record.getDistanceDriven(), 0)
    }

    func testGetEfficiencyWithCachedValue() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 12.5,
            totalCost: 43.75,
            vehicle: testVehicle
        )

        record.cachedEfficiency = 32.5
        XCTAssertEqual(record.getEfficiency(), 32.5)
    }

    func testGetEfficiencyCalculated() {
        let previousRecord = FuelingRecord(
            date: Date(timeIntervalSince1970: 1_000_000),
            odometer: 9700,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            fillUpType: .full,
            vehicle: testVehicle
        )
        let record = FuelingRecord(
            date: Date(timeIntervalSince1970: 2_000_000),
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            fillUpType: .full,
            vehicle: testVehicle
        )

        testVehicle.fuelingRecords = [record, previousRecord]
        // Should calculate: (10000 - 9700) / 10 = 30
        XCTAssertEqual(record.getEfficiency(), 30.0)
    }

    func testGetEfficiencyReturnsZeroForPartialFillUp() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            fillUpType: .partial,
            vehicle: testVehicle
        )

        record.cachedPreviousOdometer = 9700
        XCTAssertEqual(record.getEfficiency(), 0)
    }

    func testGetEfficiencyReturnsZeroForReset() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            fillUpType: .reset,
            vehicle: testVehicle
        )

        record.cachedPreviousOdometer = 9700
        XCTAssertEqual(record.getEfficiency(), 0)
    }

    func testGetEfficiencyReturnsZeroForZeroFuelAmount() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 0,
            totalCost: 0,
            fillUpType: .full,
            vehicle: testVehicle
        )

        record.cachedPreviousOdometer = 9700
        XCTAssertEqual(record.getEfficiency(), 0)
    }

    func testGetCostPerDistanceWithCachedValue() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            vehicle: testVehicle
        )

        record.cachedCostPerDistance = 0.12
        XCTAssertEqual(record.getCostPerDistance(), 0.12)
    }

    func testGetCostPerDistanceCalculated() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            vehicle: testVehicle
        )

        record.cachedPreviousOdometer = 9700
        // Cost per distance: 35 / 300 = 0.1166...
        XCTAssertEqual(record.getCostPerDistance(), 35.0 / 300.0, accuracy: 0.0001)
    }

    func testGetCostPerDistanceReturnsZeroForZeroDistance() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            vehicle: testVehicle
        )

        XCTAssertEqual(record.getCostPerDistance(), 0)
    }

}
