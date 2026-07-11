import XCTest
@testable import PumpTally

final class UnitSystemTests: XCTestCase {

    // MARK: - Raw Values

    func testImperialRawValue() {
        XCTAssertEqual(UnitSystem.imperial.rawValue, "imperial")
    }

    func testMetricRawValue() {
        XCTAssertEqual(UnitSystem.metric.rawValue, "metric")
    }

    func testInitFromRawValue() {
        XCTAssertEqual(UnitSystem(rawValue: "imperial"), .imperial)
        XCTAssertEqual(UnitSystem(rawValue: "metric"), .metric)
        XCTAssertNil(UnitSystem(rawValue: "invalid"))
    }

    // MARK: - Display Labels (Imperial)

    func testImperialDistanceUnit() {
        XCTAssertEqual(UnitSystem.imperial.distanceUnit, "mi")
    }

    func testImperialDistanceName() {
        XCTAssertEqual(UnitSystem.imperial.distanceName, "Miles")
    }

    func testImperialFuelUnit() {
        XCTAssertEqual(UnitSystem.imperial.fuelUnit, "gal")
    }

    func testImperialFuelName() {
        XCTAssertEqual(UnitSystem.imperial.fuelName, "Gallons")
    }

    func testImperialEfficiencyUnit() {
        XCTAssertEqual(UnitSystem.imperial.efficiencyUnit, "MPG")
    }

    func testImperialEfficiencyName() {
        XCTAssertEqual(UnitSystem.imperial.efficiencyName, "Miles Per Gallon")
    }

    func testImperialPricePerFuelLabel() {
        XCTAssertEqual(UnitSystem.imperial.pricePerFuelLabel, "Price per Gallon")
    }

    func testImperialCostPerDistanceLabel() {
        XCTAssertEqual(UnitSystem.imperial.costPerDistanceLabel, "Cost per Mile")
    }

    // MARK: - Display Labels (Metric)

    func testMetricDistanceUnit() {
        XCTAssertEqual(UnitSystem.metric.distanceUnit, "km")
    }

    func testMetricDistanceName() {
        XCTAssertEqual(UnitSystem.metric.distanceName, "Kilometers")
    }

    func testMetricFuelUnit() {
        XCTAssertEqual(UnitSystem.metric.fuelUnit, "L")
    }

    func testMetricFuelName() {
        XCTAssertEqual(UnitSystem.metric.fuelName, "Liters")
    }

    func testMetricEfficiencyUnit() {
        XCTAssertEqual(UnitSystem.metric.efficiencyUnit, "L/100km")
    }

    func testMetricEfficiencyName() {
        XCTAssertEqual(UnitSystem.metric.efficiencyName, "Liters per 100 km")
    }

    func testMetricPricePerFuelLabel() {
        XCTAssertEqual(UnitSystem.metric.pricePerFuelLabel, "Price per Liter")
    }

    func testMetricCostPerDistanceLabel() {
        XCTAssertEqual(UnitSystem.metric.costPerDistanceLabel, "Cost per km")
    }

    // MARK: - Display Name / Description

    func testDisplayName() {
        XCTAssertEqual(UnitSystem.imperial.displayName, "Imperial")
        XCTAssertEqual(UnitSystem.metric.displayName, "Metric")
    }

    func testDisplayDescription() {
        XCTAssertEqual(UnitSystem.imperial.displayDescription, "Miles, Gallons, MPG")
        XCTAssertEqual(UnitSystem.metric.displayDescription, "Kilometers, Liters, L/100km")
    }

    // MARK: - CaseIterable

    func testAllCases() {
        XCTAssertEqual(UnitSystem.allCases.count, 2)
        XCTAssertTrue(UnitSystem.allCases.contains(.imperial))
        XCTAssertTrue(UnitSystem.allCases.contains(.metric))
    }

    // MARK: - Conversion Factors

    func testMilesToKm() {
        XCTAssertEqual(UnitSystem.milesToKm, 1.60934, accuracy: 0.00001)
    }

    func testGallonsToLiters() {
        XCTAssertEqual(UnitSystem.gallonsToLiters, 3.78541, accuracy: 0.00001)
    }

    // MARK: - Distance Conversion

    func testConvertDistanceSameUnit() {
        let value = 100.0
        XCTAssertEqual(UnitSystem.imperial.convertDistance(from: .imperial, value: value), value)
        XCTAssertEqual(UnitSystem.metric.convertDistance(from: .metric, value: value), value)
    }

    func testConvertDistanceMilesToKm() {
        let miles = 100.0
        let km = UnitSystem.metric.convertDistance(from: .imperial, value: miles)
        XCTAssertEqual(km, 100.0 * 1.60934, accuracy: 0.001)
    }

    func testConvertDistanceKmToMiles() {
        let km = 100.0
        let miles = UnitSystem.imperial.convertDistance(from: .metric, value: km)
        XCTAssertEqual(miles, 100.0 / 1.60934, accuracy: 0.001)
    }

    func testConvertDistanceRoundTrip() {
        let original = 12345.6
        let converted = UnitSystem.metric.convertDistance(from: .imperial, value: original)
        let roundTrip = UnitSystem.imperial.convertDistance(from: .metric, value: converted)
        XCTAssertEqual(roundTrip, original, accuracy: 0.001)
    }

    // MARK: - Fuel Conversion

    func testConvertFuelSameUnit() {
        let value = 50.0
        XCTAssertEqual(UnitSystem.imperial.convertFuel(from: .imperial, value: value), value)
        XCTAssertEqual(UnitSystem.metric.convertFuel(from: .metric, value: value), value)
    }

    func testConvertFuelGallonsToLiters() {
        let gallons = 10.0
        let liters = UnitSystem.metric.convertFuel(from: .imperial, value: gallons)
        XCTAssertEqual(liters, 10.0 * 3.78541, accuracy: 0.001)
    }

    func testConvertFuelLitersToGallons() {
        let liters = 37.8541
        let gallons = UnitSystem.imperial.convertFuel(from: .metric, value: liters)
        XCTAssertEqual(gallons, 37.8541 / 3.78541, accuracy: 0.001)
    }

    func testConvertFuelRoundTrip() {
        let original = 15.5
        let converted = UnitSystem.metric.convertFuel(from: .imperial, value: original)
        let roundTrip = UnitSystem.imperial.convertFuel(from: .metric, value: converted)
        XCTAssertEqual(roundTrip, original, accuracy: 0.001)
    }

    // MARK: - Price Per Fuel Conversion

    func testConvertPricePerFuelSameUnit() {
        let value = 3.50
        XCTAssertEqual(UnitSystem.imperial.convertPricePerFuel(from: .imperial, value: value), value)
        XCTAssertEqual(UnitSystem.metric.convertPricePerFuel(from: .metric, value: value), value)
    }

    func testConvertPricePerFuelDollarPerGallonToDollarPerLiter() {
        let pricePerGallon = 3.78541 // $3.78541/gallon
        let pricePerLiter = UnitSystem.metric.convertPricePerFuel(from: .imperial, value: pricePerGallon)
        XCTAssertEqual(pricePerLiter, 1.0, accuracy: 0.001) // = 3.78541 / 3.78541
    }

    func testConvertPricePerFuelDollarPerLiterToDollarPerGallon() {
        let pricePerLiter = 1.0
        let pricePerGallon = UnitSystem.imperial.convertPricePerFuel(from: .metric, value: pricePerLiter)
        XCTAssertEqual(pricePerGallon, 3.78541, accuracy: 0.001)
    }

    func testConvertPricePerFuelRoundTrip() {
        let original = 3.459
        let converted = UnitSystem.metric.convertPricePerFuel(from: .imperial, value: original)
        let roundTrip = UnitSystem.imperial.convertPricePerFuel(from: .metric, value: converted)
        XCTAssertEqual(roundTrip, original, accuracy: 0.001)
    }

    // MARK: - Efficiency Display

    func testEfficiencyDisplayValueImperial() {
        // Imperial shows raw MPG value directly
        let rawEfficiency = 30.0
        let display = UnitSystem.imperial.efficiencyDisplayValue(from: rawEfficiency)
        XCTAssertEqual(display, 30.0)
    }

    func testEfficiencyDisplayValueMetric() {
        // Metric converts distance/fuel ratio to L/100km: 100 / ratio
        let rawEfficiency = 30.0 // 30 km/L internally
        let display = UnitSystem.metric.efficiencyDisplayValue(from: rawEfficiency)
        XCTAssertEqual(display, 100.0 / 30.0, accuracy: 0.001) // ~3.33 L/100km
    }

    func testEfficiencyDisplayValueZero() {
        XCTAssertEqual(UnitSystem.imperial.efficiencyDisplayValue(from: 0), 0)
        XCTAssertEqual(UnitSystem.metric.efficiencyDisplayValue(from: 0), 0)
    }

    func testEfficiencyDisplayFromDistanceAndFuel() {
        // Imperial: 300 miles / 10 gallons = 30 MPG
        let imperialDisplay = UnitSystem.imperial.efficiencyDisplayValue(distance: 300, fuel: 10)
        XCTAssertEqual(imperialDisplay, 30.0)

        // Metric: 300 km / 10 L = 30 km/L -> display as 100/30 = 3.33 L/100km
        let metricDisplay = UnitSystem.metric.efficiencyDisplayValue(distance: 300, fuel: 10)
        XCTAssertEqual(metricDisplay, 100.0 / 30.0, accuracy: 0.001)
    }

    func testEfficiencyDisplayFromZeroValues() {
        XCTAssertEqual(UnitSystem.imperial.efficiencyDisplayValue(distance: 0, fuel: 10), 0)
        XCTAssertEqual(UnitSystem.imperial.efficiencyDisplayValue(distance: 300, fuel: 0), 0)
        XCTAssertEqual(UnitSystem.metric.efficiencyDisplayValue(distance: 0, fuel: 10), 0)
        XCTAssertEqual(UnitSystem.metric.efficiencyDisplayValue(distance: 300, fuel: 0), 0)
    }

    // MARK: - Codable

    func testEncodeDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for unit in UnitSystem.allCases {
            let encoded = try encoder.encode(unit)
            let decoded = try decoder.decode(UnitSystem.self, from: encoded)
            XCTAssertEqual(unit, decoded)
        }
    }

    // MARK: - Unit Conversion Integration

    func testFullConversionImperialToMetric() {
        // Simulate converting a record from Imperial to Metric
        let odometerMiles = 12500.0
        let fuelGallons = 10.5
        let pricePerGallon = 3.459
        let totalCost = 36.32

        let odometerKm = UnitSystem.metric.convertDistance(from: .imperial, value: odometerMiles)
        let fuelLiters = UnitSystem.metric.convertFuel(from: .imperial, value: fuelGallons)
        let pricePerLiter = UnitSystem.metric.convertPricePerFuel(from: .imperial, value: pricePerGallon)

        // Verify conversions are reasonable
        XCTAssertGreaterThan(odometerKm, odometerMiles) // km > miles
        XCTAssertGreaterThan(fuelLiters, fuelGallons) // liters > gallons
        XCTAssertLessThan(pricePerLiter, pricePerGallon) // $/L < $/gal

        // Total cost should be preserved: fuelAmount * pricePerFuelUnit
        let newTotalCost = fuelLiters * pricePerLiter
        XCTAssertEqual(newTotalCost, totalCost, accuracy: 0.01)
    }

    func testFullConversionMetricToImperial() {
        // Simulate converting a record from Metric to Imperial
        let odometerKm = 20000.0
        let fuelLiters = 40.0
        let pricePerLiter = 0.90
        let totalCost = 36.0

        let odometerMiles = UnitSystem.imperial.convertDistance(from: .metric, value: odometerKm)
        let fuelGallons = UnitSystem.imperial.convertFuel(from: .metric, value: fuelLiters)
        let pricePerGallon = UnitSystem.imperial.convertPricePerFuel(from: .metric, value: pricePerLiter)

        // Verify conversions are reasonable
        XCTAssertLessThan(odometerMiles, odometerKm) // miles < km
        XCTAssertLessThan(fuelGallons, fuelLiters) // gallons < liters
        XCTAssertGreaterThan(pricePerGallon, pricePerLiter) // $/gal > $/L

        // Total cost should be preserved
        let newTotalCost = fuelGallons * pricePerGallon
        XCTAssertEqual(newTotalCost, totalCost, accuracy: 0.01)
    }
}
