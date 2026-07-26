import Foundation

/// Canonical, side-effect-free rules for deciding whether a fueling interval
/// has a trustworthy efficiency value.
enum FuelEfficiencyPolicy {
    /// Returns the raw distance-per-fuel efficiency for an interval, or `nil`
    /// when the interval is not eligible.
    ///
    /// The first record is always a baseline, even if it is a legacy partial
    /// or reset record. After that, both adjacent records must be full fill-ups.
    static func rawEfficiency(
        distanceDriven: Double,
        fuelAmount: Double,
        currentFillUpType: FillUpType,
        previousFillUpType: FillUpType?,
        previousIsFirstRecord: Bool
    ) -> Double? {
        guard currentFillUpType == .full,
              establishesBaseline(
                  fillUpType: previousFillUpType,
                  isFirstRecord: previousIsFirstRecord
              ),
              distanceDriven > 0,
              fuelAmount > 0 else {
            return nil
        }

        return distanceDriven / fuelAmount
    }

    private static func establishesBaseline(
        fillUpType: FillUpType?,
        isFirstRecord: Bool
    ) -> Bool {
        isFirstRecord || fillUpType == .full
    }
}
