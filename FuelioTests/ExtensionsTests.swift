import XCTest
@testable import Fuelio

final class ExtensionsTests: XCTestCase {

    // MARK: - Double Extensions Tests

    // MARK: Currency Formatting

    func testCurrencyFormattedPositiveValue() {
        let value = 3.45
        let formatted = value.currencyFormatted

        // Currency format depends on locale, but should contain the value
        XCTAssertTrue(formatted.contains("3") || formatted.contains("45"))
    }

    func testCurrencyFormattedZero() {
        let value = 0.0
        let formatted = value.currencyFormatted

        XCTAssertFalse(formatted.isEmpty)
    }

    func testCurrencyFormattedNegativeValue() {
        let value = -25.50
        let formatted = value.currencyFormatted

        // Should handle negative values
        XCTAssertFalse(formatted.isEmpty)
    }

    func testCurrencyFormattedLargeValue() {
        let value = 1234567.89
        let formatted = value.currencyFormatted

        XCTAssertFalse(formatted.isEmpty)
    }

    func testCurrencyFormattedSmallValue() {
        let value = 0.01
        let formatted = value.currencyFormatted

        XCTAssertFalse(formatted.isEmpty)
    }

    // MARK: Decimal Formatting

    func testFormattedWithZeroDecimals() {
        let value = 3.456
        let formatted = value.formatted(decimals: 0)

        XCTAssertEqual(formatted, "3")
    }

    func testFormattedWithOneDecimal() {
        let value = 3.456
        let formatted = value.formatted(decimals: 1)

        XCTAssertEqual(formatted, "3.5")
    }

    func testFormattedWithTwoDecimals() {
        let value = 3.456
        let formatted = value.formatted(decimals: 2)

        XCTAssertEqual(formatted, "3.46")
    }

    func testFormattedWithThreeDecimals() {
        let value = 3.4567
        let formatted = value.formatted(decimals: 3)

        XCTAssertEqual(formatted, "3.457")
    }

    func testFormattedWithMoreDecimalsThanValue() {
        let value = 3.5
        let formatted = value.formatted(decimals: 4)

        XCTAssertEqual(formatted, "3.5000")
    }

    func testFormattedZero() {
        let value = 0.0
        let formatted = value.formatted(decimals: 2)

        XCTAssertEqual(formatted, "0.00")
    }

    func testFormattedNegativeValue() {
        let value = -25.678
        let formatted = value.formatted(decimals: 2)

        XCTAssertEqual(formatted, "-25.68")
    }

    func testFormattedLargeValue() {
        let value = 1234567.89
        let formatted = value.formatted(decimals: 2)

        XCTAssertEqual(formatted, "1234567.89")
    }

    func testFormattedRoundingUp() {
        let value = 3.556
        let formatted = value.formatted(decimals: 2)

        // Standard rounding - 3.556 rounds up to 3.56
        XCTAssertEqual(formatted, "3.56")
    }

    func testFormattedRoundingDown() {
        let value = 3.554
        let formatted = value.formatted(decimals: 2)

        XCTAssertEqual(formatted, "3.55")
    }

    // MARK: - Array Extensions Tests

    // MARK: Total Cost

    func testTotalCostEmptyArray() {
        let records: [FuelingRecord] = []

        XCTAssertEqual(records.totalCost, 0)
    }

    func testTotalCostSingleRecord() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0
        )

        let records = [record]

        XCTAssertEqual(records.totalCost, 35.0)
    }

    func testTotalCostMultipleRecords() {
        let record1 = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0
        )

        let record2 = FuelingRecord(
            currentMiles: 10300,
            pricePerGallon: 3.75,
            gallons: 12.0,
            totalCost: 45.0
        )

        let record3 = FuelingRecord(
            currentMiles: 10600,
            pricePerGallon: 4.00,
            gallons: 8.0,
            totalCost: 32.0
        )

        let records = [record1, record2, record3]

        XCTAssertEqual(records.totalCost, 112.0)
    }

    func testTotalCostWithZeroCostRecord() {
        let record1 = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0
        )

        let record2 = FuelingRecord(
            currentMiles: 10300,
            pricePerGallon: 0,
            gallons: 0,
            totalCost: 0
        )

        let records = [record1, record2]

        XCTAssertEqual(records.totalCost, 35.0)
    }

    // MARK: Total Miles

    func testTotalMilesEmptyArray() {
        let records: [FuelingRecord] = []

        XCTAssertEqual(records.totalMiles, 0)
    }

    func testTotalMilesSingleRecordNoCachedMiles() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0
        )

        // No cached miles driven
        let records = [record]

        XCTAssertEqual(records.totalMiles, 0)
    }

    func testTotalMilesSingleRecordWithCachedMiles() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0
        )
        record.cachedMilesDriven = 300

        let records = [record]

        XCTAssertEqual(records.totalMiles, 300)
    }

    func testTotalMilesMultipleRecordsWithCachedMiles() {
        let record1 = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0
        )
        record1.cachedMilesDriven = 0 // First record has no previous

        let record2 = FuelingRecord(
            currentMiles: 10300,
            pricePerGallon: 3.75,
            gallons: 12.0,
            totalCost: 45.0
        )
        record2.cachedMilesDriven = 300

        let record3 = FuelingRecord(
            currentMiles: 10600,
            pricePerGallon: 4.00,
            gallons: 8.0,
            totalCost: 32.0
        )
        record3.cachedMilesDriven = 300

        let records = [record1, record2, record3]

        XCTAssertEqual(records.totalMiles, 600)
    }

    func testTotalMilesCalculatesFromCachedPreviousMiles() {
        let record1 = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0
        )

        let record2 = FuelingRecord(
            currentMiles: 10300,
            pricePerGallon: 3.75,
            gallons: 12.0,
            totalCost: 45.0
        )
        record2.cachedPreviousMiles = 10000

        let records = [record1, record2]

        // getMilesDriven() should calculate from cachedPreviousMiles
        XCTAssertEqual(records.totalMiles, 300)
    }

    // MARK: Total Gallons

    func testTotalGallonsEmptyArray() {
        let records: [FuelingRecord] = []

        XCTAssertEqual(records.totalGallons, 0)
    }

    func testTotalGallonsSingleRecord() {
        let record = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.5,
            totalCost: 36.75
        )

        let records = [record]

        XCTAssertEqual(records.totalGallons, 10.5)
    }

    func testTotalGallonsMultipleRecords() {
        let record1 = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0
        )

        let record2 = FuelingRecord(
            currentMiles: 10300,
            pricePerGallon: 3.75,
            gallons: 12.5,
            totalCost: 46.875
        )

        let record3 = FuelingRecord(
            currentMiles: 10600,
            pricePerGallon: 4.00,
            gallons: 8.3,
            totalCost: 33.2
        )

        let records = [record1, record2, record3]

        XCTAssertEqual(records.totalGallons, 30.8, accuracy: 0.001)
    }

    func testTotalGallonsWithZeroGallonRecord() {
        let record1 = FuelingRecord(
            currentMiles: 10000,
            pricePerGallon: 3.50,
            gallons: 10.0,
            totalCost: 35.0
        )

        let record2 = FuelingRecord(
            currentMiles: 10300,
            pricePerGallon: 3.75,
            gallons: 0,
            totalCost: 0
        )

        let records = [record1, record2]

        XCTAssertEqual(records.totalGallons, 10.0)
    }

    // MARK: - Edge Cases

    func testArrayExtensionsWithLargeDataset() {
        var records: [FuelingRecord] = []

        for i in 0..<1000 {
            let record = FuelingRecord(
                currentMiles: Double(10000 + i * 300),
                pricePerGallon: 3.50,
                gallons: 10.0,
                totalCost: 35.0
            )
            record.cachedMilesDriven = i > 0 ? 300 : 0
            records.append(record)
        }

        XCTAssertEqual(records.totalCost, 35000.0)
        XCTAssertEqual(records.totalGallons, 10000.0)
        XCTAssertEqual(records.totalMiles, 300 * 999)
    }

    func testDoubleFormattedWithVeryLargeDecimals() {
        let value = 3.14159265358979
        let formatted = value.formatted(decimals: 10)

        XCTAssertEqual(formatted, "3.1415926536")
    }
}

