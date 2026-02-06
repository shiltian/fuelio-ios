import XCTest
import SwiftData
@testable import Fuelio

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
        XCTAssertFalse(record.isReset)
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

        XCTAssertTrue(record.isReset)
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
        XCTAssertFalse(record.isReset)
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
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            fillUpType: .full,
            vehicle: testVehicle
        )

        record.cachedPreviousOdometer = 9700
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

    // MARK: - CSV Export Tests

    func testToCSVRow() {
        let date = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")!

        let record = FuelingRecord(
            date: date,
            odometer: 12500,
            pricePerFuelUnit: 3.459,
            fuelAmount: 10.5,
            totalCost: 36.32,
            fillUpType: .full,
            notes: "Test note",
            vehicle: testVehicle
        )

        let csvRow = record.toCSVRow()

        XCTAssertTrue(csvRow.contains("2024-01-15"))
        XCTAssertTrue(csvRow.contains("12500.0"))
        XCTAssertTrue(csvRow.contains("3.459"))
        XCTAssertTrue(csvRow.contains("10.5"))
        XCTAssertTrue(csvRow.contains("36.32"))
        XCTAssertTrue(csvRow.contains("full"))
        XCTAssertTrue(csvRow.contains("Test note"))
    }

    func testToCSVRowWithQuotesInNotes() {
        let date = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")!

        let record = FuelingRecord(
            date: date,
            odometer: 12500,
            pricePerFuelUnit: 3.459,
            fuelAmount: 10.5,
            totalCost: 36.32,
            fillUpType: .full,
            notes: "Note with \"quotes\"",
            vehicle: testVehicle
        )

        let csvRow = record.toCSVRow()
        XCTAssertTrue(csvRow.contains("\"\"quotes\"\""))
    }

    func testToCSVRowWithNoNotes() {
        let date = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")!

        let record = FuelingRecord(
            date: date,
            odometer: 12500,
            pricePerFuelUnit: 3.459,
            fuelAmount: 10.5,
            totalCost: 36.32,
            fillUpType: .full,
            notes: nil,
            vehicle: testVehicle
        )

        let csvRow = record.toCSVRow()
        XCTAssertTrue(csvRow.hasSuffix(",\"\""))
    }

    // MARK: - CSV Import Tests

    func testFromCSVRowValidData() {
        let csvRow = "2024-01-15T10:30:00Z,12500,3.459,10.5,36.32,full,Test note"

        let record = FuelingRecord.fromCSVRow(csvRow, vehicle: testVehicle)

        XCTAssertNotNil(record)
        XCTAssertEqual(record?.odometer, 12500)
        XCTAssertEqual(record?.pricePerFuelUnit, 3.459)
        XCTAssertEqual(record?.fuelAmount, 10.5)
        XCTAssertEqual(record?.totalCost, 36.32)
        XCTAssertEqual(record?.fillUpType, .full)
        XCTAssertEqual(record?.notes, "Test note")
    }

    func testFromCSVRowWithPartialFillUp() {
        let csvRow = "2024-01-15T10:30:00Z,12500,3.459,10.5,36.32,partial,Note"
        let record = FuelingRecord.fromCSVRow(csvRow, vehicle: testVehicle)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.fillUpType, .partial)
    }

    func testFromCSVRowWithResetFillUp() {
        let csvRow = "2024-01-15T10:30:00Z,12500,3.459,10.5,36.32,reset,Note"
        let record = FuelingRecord.fromCSVRow(csvRow, vehicle: testVehicle)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.fillUpType, .reset)
    }

    func testFromCSVRowWithLegacyTrueFormat() {
        let csvRow = "2024-01-15T10:30:00Z,12500,3.459,10.5,36.32,true,Note"
        let record = FuelingRecord.fromCSVRow(csvRow, vehicle: testVehicle)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.fillUpType, .partial)
    }

    func testFromCSVRowWithLegacyFalseFormat() {
        let csvRow = "2024-01-15T10:30:00Z,12500,3.459,10.5,36.32,false,Note"
        let record = FuelingRecord.fromCSVRow(csvRow, vehicle: testVehicle)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.fillUpType, .full)
    }

    func testFromCSVRowWithMissingFillUpType() {
        let csvRow = "2024-01-15T10:30:00Z,12500,3.459,10.5,36.32"
        let record = FuelingRecord.fromCSVRow(csvRow, vehicle: testVehicle)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.fillUpType, .full)
        XCTAssertNil(record?.notes)
    }

    func testFromCSVRowWithEmptyNotes() {
        let csvRow = "2024-01-15T10:30:00Z,12500,3.459,10.5,36.32,full,"
        let record = FuelingRecord.fromCSVRow(csvRow, vehicle: testVehicle)
        XCTAssertNotNil(record)
        XCTAssertNil(record?.notes)
    }

    func testFromCSVRowInvalidDate() {
        let csvRow = "invalid-date,12500,3.459,10.5,36.32,full,Note"
        let record = FuelingRecord.fromCSVRow(csvRow, vehicle: testVehicle)
        XCTAssertNil(record)
    }

    func testFromCSVRowInvalidNumbers() {
        let csvRow = "2024-01-15T10:30:00Z,not-a-number,3.459,10.5,36.32,full,Note"
        let record = FuelingRecord.fromCSVRow(csvRow, vehicle: testVehicle)
        XCTAssertNil(record)
    }

    func testFromCSVRowTooFewComponents() {
        let csvRow = "2024-01-15T10:30:00Z,12500,3.459,10.5"
        let record = FuelingRecord.fromCSVRow(csvRow, vehicle: testVehicle)
        XCTAssertNil(record)
    }

    func testFromCSVRowWithQuotedNotes() {
        let csvRow = "2024-01-15T10:30:00Z,12500,3.459,10.5,36.32,full,\"Note with, comma\""
        let record = FuelingRecord.fromCSVRow(csvRow, vehicle: testVehicle)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.notes, "Note with, comma")
    }

    // MARK: - CSV Header Test

    func testCSVHeader() {
        let expectedHeader = "date,odometer,pricePerFuelUnit,fuelAmount,totalCost,fillUpType,notes"
        XCTAssertEqual(FuelingRecord.csvHeader, expectedHeader)
    }
}
