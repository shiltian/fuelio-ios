import XCTest
@testable import PumpTally

final class ExtensionsTests: XCTestCase {
    private let testVehicle = Vehicle(name: "Test Car")

    // MARK: - Double Extensions Tests

    // MARK: Currency Formatting

    func testCurrencyFormattedPositiveValue() {
        let value = 3.45
        let formatted = value.currencyFormatted

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

        XCTAssertEqual(formatted, "3.56")
    }

    func testFormattedRoundingDown() {
        let value = 3.554
        let formatted = value.formatted(decimals: 2)

        XCTAssertEqual(formatted, "3.55")
    }

    func testEditableDecimalStringOmitsTrailingZeroForWholeValue() {
        XCTAssertEqual(45_000.0.editableDecimalString, "45000")
    }

    func testEditableDecimalStringPreservesFractionalValue() {
        XCTAssertEqual(45_000.25.editableDecimalString, "45000.25")
    }

    // MARK: - Array Extensions Tests

    // MARK: Total Cost

    func testTotalCostEmptyArray() {
        let records: [FuelingRecord] = []

        XCTAssertEqual(records.totalCost, 0)
    }

    func testTotalCostSingleRecord() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            vehicle: testVehicle
        )

        let records = [record]

        XCTAssertEqual(records.totalCost, 35.0)
    }

    func testTotalCostMultipleRecords() {
        let record1 = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            vehicle: testVehicle
        )

        let record2 = FuelingRecord(
            odometer: 10300,
            pricePerFuelUnit: 3.75,
            fuelAmount: 12.0,
            totalCost: 45.0,
            vehicle: testVehicle
        )

        let record3 = FuelingRecord(
            odometer: 10600,
            pricePerFuelUnit: 4.00,
            fuelAmount: 8.0,
            totalCost: 32.0,
            vehicle: testVehicle
        )

        let records = [record1, record2, record3]

        XCTAssertEqual(records.totalCost, 112.0)
    }

    func testTotalCostWithZeroCostRecord() {
        let record1 = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            vehicle: testVehicle
        )

        let record2 = FuelingRecord(
            odometer: 10300,
            pricePerFuelUnit: 0,
            fuelAmount: 0,
            totalCost: 0,
            vehicle: testVehicle
        )

        let records = [record1, record2]

        XCTAssertEqual(records.totalCost, 35.0)
    }

    // MARK: Total Distance

    func testTotalDistanceEmptyArray() {
        let records: [FuelingRecord] = []

        XCTAssertEqual(records.totalDistance, 0)
    }

    func testTotalDistanceSingleRecordNoCachedDistance() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            vehicle: testVehicle
        )

        let records = [record]

        XCTAssertEqual(records.totalDistance, 0)
    }

    func testTotalDistanceSingleRecordWithCachedDistance() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            vehicle: testVehicle
        )
        record.cachedDistanceDriven = 300

        let records = [record]

        XCTAssertEqual(records.totalDistance, 300)
    }

    func testTotalDistanceMultipleRecordsWithCachedDistance() {
        let record1 = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            vehicle: testVehicle
        )
        record1.cachedDistanceDriven = 0

        let record2 = FuelingRecord(
            odometer: 10300,
            pricePerFuelUnit: 3.75,
            fuelAmount: 12.0,
            totalCost: 45.0,
            vehicle: testVehicle
        )
        record2.cachedDistanceDriven = 300

        let record3 = FuelingRecord(
            odometer: 10600,
            pricePerFuelUnit: 4.00,
            fuelAmount: 8.0,
            totalCost: 32.0,
            vehicle: testVehicle
        )
        record3.cachedDistanceDriven = 300

        let records = [record1, record2, record3]

        XCTAssertEqual(records.totalDistance, 600)
    }

    func testTotalDistanceCalculatesFromCachedPreviousOdometer() {
        let record1 = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            vehicle: testVehicle
        )

        let record2 = FuelingRecord(
            odometer: 10300,
            pricePerFuelUnit: 3.75,
            fuelAmount: 12.0,
            totalCost: 45.0,
            vehicle: testVehicle
        )
        record2.cachedPreviousOdometer = 10000

        let records = [record1, record2]

        XCTAssertEqual(records.totalDistance, 300)
    }

    // MARK: Total Fuel

    func testTotalFuelEmptyArray() {
        let records: [FuelingRecord] = []

        XCTAssertEqual(records.totalFuel, 0)
    }

    func testTotalFuelSingleRecord() {
        let record = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.5,
            totalCost: 36.75,
            vehicle: testVehicle
        )

        let records = [record]

        XCTAssertEqual(records.totalFuel, 10.5)
    }

    func testTotalFuelMultipleRecords() {
        let record1 = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            vehicle: testVehicle
        )

        let record2 = FuelingRecord(
            odometer: 10300,
            pricePerFuelUnit: 3.75,
            fuelAmount: 12.5,
            totalCost: 46.875,
            vehicle: testVehicle
        )

        let record3 = FuelingRecord(
            odometer: 10600,
            pricePerFuelUnit: 4.00,
            fuelAmount: 8.3,
            totalCost: 33.2,
            vehicle: testVehicle
        )

        let records = [record1, record2, record3]

        XCTAssertEqual(records.totalFuel, 30.8, accuracy: 0.001)
    }

    func testTotalFuelWithZeroFuelRecord() {
        let record1 = FuelingRecord(
            odometer: 10000,
            pricePerFuelUnit: 3.50,
            fuelAmount: 10.0,
            totalCost: 35.0,
            vehicle: testVehicle
        )

        let record2 = FuelingRecord(
            odometer: 10300,
            pricePerFuelUnit: 3.75,
            fuelAmount: 0,
            totalCost: 0,
            vehicle: testVehicle
        )

        let records = [record1, record2]

        XCTAssertEqual(records.totalFuel, 10.0)
    }

    // MARK: - Edge Cases

    func testArrayExtensionsWithLargeDataset() {
        var records: [FuelingRecord] = []

        for i in 0..<1000 {
            let record = FuelingRecord(
                odometer: Double(10000 + i * 300),
                pricePerFuelUnit: 3.50,
                fuelAmount: 10.0,
                totalCost: 35.0,
                vehicle: testVehicle
            )
            record.cachedDistanceDriven = i > 0 ? 300 : 0
            records.append(record)
        }

        XCTAssertEqual(records.totalCost, 35000.0)
        XCTAssertEqual(records.totalFuel, 10000.0)
        XCTAssertEqual(records.totalDistance, 300 * 999)
    }

    func testDoubleFormattedWithVeryLargeDecimals() {
        let value = 3.14159265358979
        let formatted = value.formatted(decimals: 10)

        XCTAssertEqual(formatted, "3.1415926536")
    }
}
