import XCTest
@testable import PumpTally

final class ExtensionsTests: XCTestCase {

    // MARK: - Currency Formatting

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

    // MARK: - Editable Decimal Strings

    func testEditableDecimalStringOmitsTrailingZeroForWholeValue() {
        XCTAssertEqual(45_000.0.editableDecimalString, "45000")
    }

    func testEditableDecimalStringPreservesFractionalValue() {
        XCTAssertEqual(45_000.25.editableDecimalString, "45000.25")
    }
}
