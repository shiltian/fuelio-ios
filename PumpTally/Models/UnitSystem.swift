import Foundation

/// Represents the measurement unit system for a vehicle
enum UnitSystem: String, Codable, CaseIterable {
    case imperial // miles, gallons, MPG
    case metric   // km, liters, L/100km

    // MARK: - Display Labels

    /// Short distance unit: "mi" or "km"
    var distanceUnit: String {
        switch self {
        case .imperial: return "mi"
        case .metric: return "km"
        }
    }

    /// Full distance name: "Miles" or "Kilometers"
    var distanceName: String {
        switch self {
        case .imperial: return String(localized: "Miles")
        case .metric: return String(localized: "Kilometers")
        }
    }

    /// Short fuel unit: "gal" or "L"
    var fuelUnit: String {
        switch self {
        case .imperial: return "gal"
        case .metric: return "L"
        }
    }

    /// Full fuel name: "Gallons" or "Liters"
    var fuelName: String {
        switch self {
        case .imperial: return String(localized: "Gallons")
        case .metric: return String(localized: "Liters")
        }
    }

    /// Efficiency unit: "MPG" or "L/100km"
    var efficiencyUnit: String {
        switch self {
        case .imperial: return "MPG"
        case .metric: return "L/100km"
        }
    }

    /// Full efficiency name: "Miles Per Gallon" or "Liters per 100 km"
    var efficiencyName: String {
        switch self {
        case .imperial: return String(localized: "Miles Per Gallon")
        case .metric: return String(localized: "Liters per 100 km")
        }
    }

    /// Label for price per fuel unit: "Price per Gallon" or "Price per Liter"
    var pricePerFuelLabel: String {
        switch self {
        case .imperial: return String(localized: "Price per Gallon")
        case .metric: return String(localized: "Price per Liter")
        }
    }

    /// Short price per fuel unit: "$/gal" or "$/L"
    var pricePerFuelShort: String {
        switch self {
        case .imperial: return "/gal"
        case .metric: return "/L"
        }
    }

    /// Label for cost per distance: "Cost per Mile" or "Cost per km"
    var costPerDistanceLabel: String {
        switch self {
        case .imperial: return String(localized: "Cost per Mile")
        case .metric: return String(localized: "Cost per km")
        }
    }

    /// Short cost per distance: "/mile" or "/km"
    var costPerDistanceShort: String {
        switch self {
        case .imperial: return "/mile"
        case .metric: return "/km"
        }
    }

    /// Average cost per distance label for dashboard: "Avg $/Mile" or "Avg $/km"
    var avgCostPerDistanceLabel: String {
        switch self {
        case .imperial: return String(localized: "Avg $/Mile")
        case .metric: return String(localized: "Avg $/km")
        }
    }

    /// Display name for the unit system itself
    var displayName: String {
        switch self {
        case .imperial: return String(localized: "Imperial")
        case .metric: return String(localized: "Metric")
        }
    }

    /// Description of what the unit system uses
    var displayDescription: String {
        switch self {
        case .imperial: return String(localized: "Miles, Gallons, MPG")
        case .metric: return String(localized: "Kilometers, Liters, L/100km")
        }
    }

    /// Short label for price per fuel unit: "Price/Gallon" or "Price/Liter"
    var pricePerFuelShortLabel: String {
        switch self {
        case .imperial: return String(localized: "Price/Gallon")
        case .metric: return String(localized: "Price/Liter")
        }
    }

    // MARK: - Conversion Factors

    /// Miles to kilometers
    static let milesToKm: Double = 1.60934

    /// Gallons to liters
    static let gallonsToLiters: Double = 3.78541

    // MARK: - Efficiency Display

    /// Convert raw efficiency value (distance/fuel ratio) to a display value.
    ///
    /// The cache always stores `distance / fuel` regardless of unit system.
    /// - Imperial: return as-is (MPG, higher = better)
    /// - Metric: convert to L/100km = `100.0 / (distance/fuel)` (lower = better)
    func efficiencyDisplayValue(from rawEfficiency: Double) -> Double {
        guard rawEfficiency > 0 else { return 0 }
        switch self {
        case .imperial:
            return rawEfficiency
        case .metric:
            return 100.0 / rawEfficiency
        }
    }

    /// Compute efficiency display value from distance and fuel amounts
    func efficiencyDisplayValue(distance: Double, fuel: Double) -> Double {
        guard distance > 0, fuel > 0 else { return 0 }
        let rawRatio = distance / fuel
        return efficiencyDisplayValue(from: rawRatio)
    }

    // MARK: - Unit Conversion

    /// Convert a distance value from another unit system to this one
    func convertDistance(from source: UnitSystem, value: Double) -> Double {
        if source == self { return value }
        switch self {
        case .metric:
            // miles -> km
            return value * UnitSystem.milesToKm
        case .imperial:
            // km -> miles
            return value / UnitSystem.milesToKm
        }
    }

    /// Convert a fuel amount from another unit system to this one
    func convertFuel(from source: UnitSystem, value: Double) -> Double {
        if source == self { return value }
        switch self {
        case .metric:
            // gallons -> liters
            return value * UnitSystem.gallonsToLiters
        case .imperial:
            // liters -> gallons
            return value / UnitSystem.gallonsToLiters
        }
    }

    /// Convert a price-per-fuel-unit from another unit system to this one
    func convertPricePerFuel(from source: UnitSystem, value: Double) -> Double {
        if source == self { return value }
        switch self {
        case .metric:
            // $/gallon -> $/liter (price goes down because liters are smaller)
            return value / UnitSystem.gallonsToLiters
        case .imperial:
            // $/liter -> $/gallon (price goes up because gallons are larger)
            return value * UnitSystem.gallonsToLiters
        }
    }
}
