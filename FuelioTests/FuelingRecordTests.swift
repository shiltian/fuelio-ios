import XCTest
import SwiftData
@testable import Fuelio

final class FuelingRecordTests: XCTestCase {
    private let testVehicle = Vehicle(name: "Test Car")

    // MARK: - Initialization Tests

    func testInitializationWithDefaultValues() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 12.5,
            totalCost: 43.75
        )

        XCTAssertEqual(record.currentMiles, 10000)
        XCTAssertEqual(record.pricePerGallon, 3.50)
        XCTAssertEqual(record.gallons, 12.5)
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
            currentMiles: 25000,
            pricePerGallon: 4.25,
            gallons: 15.0,
            totalCost: 63.75,
            fillUpType: .partial,
            notes: "Test note",
            createdAt: customDate
        )

        XCTAssertEqual(record.id, customId)
        XCTAssertEqual(record.date, customDate)
        XCTAssertEqual(record.currentMiles, 25000)
        XCTAssertEqual(record.pricePerGallon, 4.25)
        XCTAssertEqual(record.gallons, 15.0)
        XCTAssertEqual(record.totalCost, 63.75)
        XCTAssertEqual(record.fillUpType, .partial)
        XCTAssertEqual(record.notes, "Test note")
    }

    // MARK: - Fill-up Type Tests

    func testFillUpTypeAccessor() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 12.5,
            totalCost: 43.75,
            fillUpType: .full
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
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 12.5,
            totalCost: 43.75,
            fillUpType: .partial
        )

        XCTAssertTrue(record.isPartialFillUp)
        XCTAssertFalse(record.isFullFillUp)
        XCTAssertFalse(record.isReset)
    }

    func testIsReset() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 12.5,
            totalCost: 43.75,
            fillUpType: .reset
        )

        XCTAssertTrue(record.isReset)
        XCTAssertFalse(record.isFullFillUp)
        XCTAssertFalse(record.isPartialFillUp)
    }

    func testIsFullFillUp() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 12.5,
            totalCost: 43.75,
            fillUpType: .full
        )

        XCTAssertTrue(record.isFullFillUp)
        XCTAssertFalse(record.isPartialFillUp)
        XCTAssertFalse(record.isReset)
    }

    // MARK: - Cached Value Tests

    func testGetPreviousMilesWithCachedValue() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 12.5,
            totalCost: 43.75
        )

        record.cachedPreviousMiles = 9500
        XCTAssertEqual(record.getPreviousMiles(), 9500)
    }

    func testGetPreviousMilesWithFallback() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 12.5,
            totalCost: 43.75
        )

        XCTAssertEqual(record.getPreviousMiles(fallback: 100), 100)
    }

    func testGetMilesDrivenWithCachedValue() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 12.5,
            totalCost: 43.75
        )

        record.cachedMilesDriven = 500
        XCTAssertEqual(record.getMilesDriven(), 500)
    }

    func testGetMilesDrivenCalculated() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 12.5,
            totalCost: 43.75
        )

        record.cachedPreviousMiles = 9500
        XCTAssertEqual(record.getMilesDriven(), 500)
    }

    func testGetMilesDrivenNoPreviousMiles() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 12.5,
            totalCost: 43.75
        )

        XCTAssertEqual(record.getMilesDriven(), 0)
    }

    func testGetMPGWithCachedValue() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 12.5,
            totalCost: 43.75
        )

        record.cachedMPG = 32.5
        XCTAssertEqual(record.getMPG(), 32.5)
    }

    func testGetMPGCalculated() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0,
            fillUpType: .full
        )

        record.cachedPreviousMiles = 9700
        // Should calculate: (10000 - 9700) / 10 = 30 MPG
        XCTAssertEqual(record.getMPG(), 30.0)
    }

    func testGetMPGReturnsZeroForPartialFillUp() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0,
            fillUpType: .partial
        )

        record.cachedPreviousMiles = 9700
        XCTAssertEqual(record.getMPG(), 0)
    }

    func testGetMPGReturnsZeroForReset() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0,
            fillUpType: .reset
        )

        record.cachedPreviousMiles = 9700
        XCTAssertEqual(record.getMPG(), 0)
    }

    func testGetMPGReturnsZeroForZeroGallons() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 0,
            totalCost: 0,
            fillUpType: .full
        )

        record.cachedPreviousMiles = 9700
        XCTAssertEqual(record.getMPG(), 0)
    }

    func testGetCostPerMileWithCachedValue() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0
        )

        record.cachedCostPerMile = 0.12
        XCTAssertEqual(record.getCostPerMile(), 0.12)
    }

    func testGetCostPerMileCalculated() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0
        )

        record.cachedPreviousMiles = 9700
        // Cost per mile: 35 / 300 = 0.1166...
        XCTAssertEqual(record.getCostPerMile(), 35.0 / 300.0, accuracy: 0.0001)
    }

    func testGetCostPerMileReturnsZeroForZeroMiles() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0
        )

        XCTAssertEqual(record.getCostPerMile(), 0)
    }

    // MARK: - CSV Export Tests

    func testToCSVRow() {
        let date = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")!

        let record = FuelingRecord(
            date: date,
            currentMiles: 12500,
            pricePerGallon: 3.459,
            gallons: 10.5,
            totalCost: 36.32,
            fillUpType: .full,
            notes: "Test note"
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
            currentMiles: 12500,
            pricePerGallon: 3.459,
            gallons: 10.5,
            totalCost: 36.32,
            fillUpType: .full,
            notes: "Note with \"quotes\""
        )

        let csvRow = record.toCSVRow()

        // Quotes should be escaped as ""
        XCTAssertTrue(csvRow.contains("\"\"quotes\"\""))
    }

    func testToCSVRowWithNoNotes() {
        let date = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")!

        let record = FuelingRecord(
            date: date,
            currentMiles: 12500,
            pricePerGallon: 3.459,
            gallons: 10.5,
            totalCost: 36.32,
            fillUpType: .full,
            notes: nil
        )

        let csvRow = record.toCSVRow()

        // Should have empty quotes for notes
        XCTAssertTrue(csvRow.hasSuffix(",\"\""))
    }

    // MARK: - CSV Import Tests

    func testFromCSVRowValidData() {
        let csvRow = "2024-01-15T10:30:00Z,12500,3.459,10.5,36.32,full,Test note"

        let record = FuelingRecord.fromCSVRow(csvRow, vehicle: testVehicle)

        XCTAssertNotNil(record)
        XCTAssertEqual(record?.currentMiles, 12500)
        XCTAssertEqual(record?.pricePerGallon, 3.459)
        XCTAssertEqual(record?.gallons, 10.5)
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
        XCTAssertEqual(record?.fillUpType, .full) // Default to full
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
        let expectedHeader = "date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes"
        XCTAssertEqual(FuelingRecord.csvHeader, expectedHeader)
    }
}

