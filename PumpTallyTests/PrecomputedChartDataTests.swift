import XCTest
@testable import PumpTally

final class PrecomputedChartDataTests: XCTestCase {

    private let baseDate = Date(timeIntervalSince1970: 1_000_000)

    private func snapshot(
        index: Int,
        efficiency: Double? = nil,
        cost: Double,
        price: Double
    ) -> ChartRecordSnapshot {
        ChartRecordSnapshot(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
            date: baseDate.addingTimeInterval(Double(index) * 86_400),
            cachedEfficiency: efficiency,
            totalCost: cost,
            pricePerFuelUnit: price
        )
    }

    func testEmptyRecordsUseDefaultValues() {
        let data = PrecomputedChartData(records: [], unitSystem: .imperial)

        XCTAssertTrue(data.efficiencyData.isEmpty)
        XCTAssertTrue(data.costData.isEmpty)
        XCTAssertTrue(data.priceData.isEmpty)
        XCTAssertEqual(data.efficiencyAverage, 0)
        XCTAssertEqual(data.costAverage, 0)
        XCTAssertEqual(data.priceAverage, 0)
        XCTAssertEqual(data.efficiencyYRange, 0...40)
        XCTAssertEqual(data.costYRange, 0...100)
        XCTAssertEqual(data.priceYRange, 0...5)
    }

    func testSummariesAndRangesUseCompleteDataset() {
        let records = [
            snapshot(index: 2, efficiency: nil, cost: 100, price: 4.2),
            snapshot(index: 0, efficiency: 10, cost: 10, price: 3.1),
            snapshot(index: 1, efficiency: 20, cost: 20, price: 3.6)
        ]

        let data = PrecomputedChartData(records: records, unitSystem: .imperial)

        XCTAssertEqual(data.efficiencyAverage, 15, accuracy: 0.000_001)
        XCTAssertEqual(data.costAverage, 130.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(data.priceAverage, 10.9 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(data.efficiencyYRange, 10...20)
        XCTAssertEqual(data.costYRange, 10...100)
        XCTAssertEqual(data.priceYRange, 3...4.5)
        XCTAssertEqual(data.costData.map(\.date), data.costData.map(\.date).sorted())
    }

    func testEveryRenderedSeriesIsCappedAndDeterministic() {
        var records: [ChartRecordSnapshot] = []
        records.reserveCapacity(401)
        for index in (0..<401).reversed() {
            records.append(snapshot(
                index: index,
                efficiency: Double(index + 10),
                cost: Double(index + 1),
                price: 3 + Double(index) / 100
            ))
        }

        let first = PrecomputedChartData(records: records, unitSystem: .imperial)
        let second = PrecomputedChartData(records: records, unitSystem: .imperial)

        XCTAssertEqual(first.efficiencyData.count, PrecomputedChartData.maxTrendPoints)
        XCTAssertEqual(first.costData.count, PrecomputedChartData.maxTrendPoints)
        XCTAssertEqual(first.priceData.count, PrecomputedChartData.maxTrendPoints)
        XCTAssertEqual(first.efficiencyData, second.efficiencyData)
        XCTAssertEqual(first.costData, second.costData)
        XCTAssertEqual(first.priceData, second.priceData)
        XCTAssertFalse(first.showPoints)
        XCTAssertEqual(first.costAverage, 201, accuracy: 0.000_001)
        XCTAssertEqual(first.costYRange, 0...410)
    }

    func testMetricEfficiencyFormatConversion() {
        let records = [
            snapshot(index: 0, efficiency: 10, cost: 10, price: 3),
            snapshot(index: 1, efficiency: 20, cost: 20, price: 4)
        ]

        let litersPer100 = PrecomputedChartData(
            records: records,
            unitSystem: .metric,
            metricEfficiencyFormat: .litersPer100Kilometers
        )
        let kilometersPerLiter = PrecomputedChartData(
            records: records,
            unitSystem: .metric,
            metricEfficiencyFormat: .kilometersPerLiter
        )

        XCTAssertEqual(litersPer100.efficiencyAverage, 100.0 / 15.0, accuracy: 0.000_001)
        XCTAssertEqual(litersPer100.efficiencyData.map(\.value), [10, 5])
        XCTAssertEqual(kilometersPerLiter.efficiencyAverage, 15, accuracy: 0.000_001)
        XCTAssertEqual(kilometersPerLiter.efficiencyData.map(\.value), [10, 20])
    }
}
