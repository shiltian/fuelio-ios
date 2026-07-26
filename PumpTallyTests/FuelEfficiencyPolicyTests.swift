import XCTest
@testable import PumpTally

final class FuelEfficiencyPolicyTests: XCTestCase {
    func testFullToFullIntervalProducesEfficiency() {
        let efficiency = FuelEfficiencyPolicy.rawEfficiency(
            distanceDriven: 300,
            fuelAmount: 10,
            currentFillUpType: .full,
            previousFillUpType: .full,
            previousIsFirstRecord: false
        )

        XCTAssertEqual(efficiency, 30)
    }

    func testCurrentPartialAndResetRecordsAreIneligible() {
        for fillUpType in [FillUpType.partial, .reset] {
            XCTAssertNil(
                FuelEfficiencyPolicy.rawEfficiency(
                    distanceDriven: 300,
                    fuelAmount: 10,
                    currentFillUpType: fillUpType,
                    previousFillUpType: .full,
                    previousIsFirstRecord: false
                )
            )
        }
    }

    func testPartialAndResetBreakTheFollowingInterval() {
        for fillUpType in [FillUpType.partial, .reset] {
            XCTAssertNil(
                FuelEfficiencyPolicy.rawEfficiency(
                    distanceDriven: 300,
                    fuelAmount: 10,
                    currentFillUpType: .full,
                    previousFillUpType: fillUpType,
                    previousIsFirstRecord: false
                )
            )
        }
    }

    func testFirstRecordRemainsBaselineRegardlessOfLegacyFillUpType() {
        for fillUpType in FillUpType.allCases {
            XCTAssertEqual(
                FuelEfficiencyPolicy.rawEfficiency(
                    distanceDriven: 300,
                    fuelAmount: 10,
                    currentFillUpType: .full,
                    previousFillUpType: fillUpType,
                    previousIsFirstRecord: true
                ),
                30
            )
        }
    }

    func testNonPositiveDistanceOrFuelIsIneligible() {
        for (distance, fuel) in [(0.0, 10.0), (-1.0, 10.0), (300.0, 0.0), (300.0, -1.0)] {
            XCTAssertNil(
                FuelEfficiencyPolicy.rawEfficiency(
                    distanceDriven: distance,
                    fuelAmount: fuel,
                    currentFillUpType: .full,
                    previousFillUpType: .full,
                    previousIsFirstRecord: false
                )
            )
        }
    }

    func testMissingPreviousRecordIsIneligible() {
        XCTAssertNil(
            FuelEfficiencyPolicy.rawEfficiency(
                distanceDriven: 300,
                fuelAmount: 10,
                currentFillUpType: .full,
                previousFillUpType: nil,
                previousIsFirstRecord: false
            )
        )
    }
}
