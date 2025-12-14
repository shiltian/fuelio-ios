import XCTest
import SwiftUI
@testable import Fuelio

final class FillUpTypeTests: XCTestCase {

    // MARK: - Raw Value Tests

    func testFullRawValue() {
        XCTAssertEqual(FillUpType.full.rawValue, "full")
    }

    func testPartialRawValue() {
        XCTAssertEqual(FillUpType.partial.rawValue, "partial")
    }

    func testResetRawValue() {
        XCTAssertEqual(FillUpType.reset.rawValue, "reset")
    }

    // MARK: - Initialization from Raw Value Tests

    func testInitFromFullRawValue() {
        let fillUpType = FillUpType(rawValue: "full")
        XCTAssertEqual(fillUpType, .full)
    }

    func testInitFromPartialRawValue() {
        let fillUpType = FillUpType(rawValue: "partial")
        XCTAssertEqual(fillUpType, .partial)
    }

    func testInitFromResetRawValue() {
        let fillUpType = FillUpType(rawValue: "reset")
        XCTAssertEqual(fillUpType, .reset)
    }

    func testInitFromInvalidRawValue() {
        let fillUpType = FillUpType(rawValue: "invalid")
        XCTAssertNil(fillUpType)
    }

    func testInitFromEmptyRawValue() {
        let fillUpType = FillUpType(rawValue: "")
        XCTAssertNil(fillUpType)
    }

    // MARK: - Display Name Tests

    func testFullDisplayName() {
        XCTAssertEqual(FillUpType.full.displayName, "Full Tank")
    }

    func testPartialDisplayName() {
        XCTAssertEqual(FillUpType.partial.displayName, "Partial Fill")
    }

    func testResetDisplayName() {
        XCTAssertEqual(FillUpType.reset.displayName, "Missed Fueling")
    }

    // MARK: - Description Tests

    func testFullDescription() {
        XCTAssertEqual(FillUpType.full.description, "Filled the tank completely")
    }

    func testPartialDescription() {
        XCTAssertEqual(FillUpType.partial.description, "Didn't fill completely (affects next MPG)")
    }

    func testResetDescription() {
        XCTAssertEqual(FillUpType.reset.description, "Missed recording previous fill-up(s)")
    }

    // MARK: - Icon Tests

    func testFullIcon() {
        XCTAssertEqual(FillUpType.full.icon, "fuelpump.fill")
    }

    func testPartialIcon() {
        XCTAssertEqual(FillUpType.partial.icon, "exclamationmark.triangle.fill")
    }

    func testResetIcon() {
        XCTAssertEqual(FillUpType.reset.icon, "arrow.counterclockwise.circle.fill")
    }

    // MARK: - Color Tests

    func testFullColor() {
        XCTAssertEqual(FillUpType.full.color, .green)
    }

    func testPartialColor() {
        XCTAssertEqual(FillUpType.partial.color, .yellow)
    }

    func testResetColor() {
        XCTAssertEqual(FillUpType.reset.color, .red)
    }

    // MARK: - CaseIterable Tests

    func testAllCasesCount() {
        XCTAssertEqual(FillUpType.allCases.count, 3)
    }

    func testAllCasesContainsAllTypes() {
        let allCases = FillUpType.allCases

        XCTAssertTrue(allCases.contains(.full))
        XCTAssertTrue(allCases.contains(.partial))
        XCTAssertTrue(allCases.contains(.reset))
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for fillUpType in FillUpType.allCases {
            let encoded = try encoder.encode(fillUpType)
            let decoded = try decoder.decode(FillUpType.self, from: encoded)

            XCTAssertEqual(fillUpType, decoded)
        }
    }

    func testDecodeFromString() throws {
        let decoder = JSONDecoder()

        let fullData = "\"full\"".data(using: .utf8)!
        let partialData = "\"partial\"".data(using: .utf8)!
        let resetData = "\"reset\"".data(using: .utf8)!

        XCTAssertEqual(try decoder.decode(FillUpType.self, from: fullData), .full)
        XCTAssertEqual(try decoder.decode(FillUpType.self, from: partialData), .partial)
        XCTAssertEqual(try decoder.decode(FillUpType.self, from: resetData), .reset)
    }

    func testDecodeInvalidValueThrows() {
        let decoder = JSONDecoder()
        let invalidData = "\"invalid\"".data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(FillUpType.self, from: invalidData))
    }

    // MARK: - Equatable Tests

    func testEquality() {
        XCTAssertEqual(FillUpType.full, FillUpType.full)
        XCTAssertEqual(FillUpType.partial, FillUpType.partial)
        XCTAssertEqual(FillUpType.reset, FillUpType.reset)
    }

    func testInequality() {
        XCTAssertNotEqual(FillUpType.full, FillUpType.partial)
        XCTAssertNotEqual(FillUpType.full, FillUpType.reset)
        XCTAssertNotEqual(FillUpType.partial, FillUpType.reset)
    }
}

