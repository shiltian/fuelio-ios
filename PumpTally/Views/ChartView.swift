import SwiftUI
import Charts

// MARK: - Pre-computed Chart Data (for performance)

/// Pre-computed data point for charts
struct ChartDataPoint: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
}

/// Pre-computed chart data to avoid recalculation on every render
struct PrecomputedChartData {
    let efficiencyData: [ChartDataPoint]
    let efficiencyAverage: Double
    let efficiencyYRange: ClosedRange<Double>

    let costData: [ChartDataPoint]
    let costAverage: Double
    let costYRange: ClosedRange<Double>

    let priceData: [ChartDataPoint]
    let priceAverage: Double
    let priceYRange: ClosedRange<Double>

    let showPoints: Bool  // Only show points if data count is reasonable
    let unitSystem: UnitSystem
    let metricEfficiencyFormat: MetricEfficiencyFormat

    /// Maximum number of individual point markers to display for performance.
    /// Line, area, and bar series still use every underlying record.
    static let maxPointMarkers = 100
    /// MPG/efficiency can be noisy per fill-up; smooth only that chart for long histories.
    static let maxEfficiencyTrendPoints = 200

    init(
        records: [FuelingRecord],
        unitSystem: UnitSystem,
        metricEfficiencyFormat: MetricEfficiencyFormat = .defaultFormat
    ) {
        self.unitSystem = unitSystem
        self.metricEfficiencyFormat = metricEfficiencyFormat

        // Sort once
        let sorted = records.sorted { $0.date < $1.date }

        // Avoid visual clutter and marker overhead for larger histories.
        self.showPoints = sorted.count <= Self.maxPointMarkers

        // Pre-compute efficiency data, smoothing long MPG histories for readability.
        let allEfficiencyRecords = sorted.filter { $0.cachedEfficiency != nil && $0.cachedEfficiency! > 0 }
        if allEfficiencyRecords.count > Self.maxEfficiencyTrendPoints {
            self.efficiencyData = Self.createAveragedEfficiencyDataPoints(
                from: allEfficiencyRecords,
                targetCount: Self.maxEfficiencyTrendPoints,
                unitSystem: unitSystem,
                metricEfficiencyFormat: metricEfficiencyFormat
            )
        } else {
            self.efficiencyData = allEfficiencyRecords.map {
                ChartDataPoint(
                    id: $0.id,
                    date: $0.date,
                    value: unitSystem.efficiencyDisplayValue(
                        from: $0.cachedEfficiency!,
                        metricFormat: metricEfficiencyFormat
                    )
                )
            }
        }

        // Calculate efficiency average from ALL valid records
        if !allEfficiencyRecords.isEmpty {
            let rawAvg = allEfficiencyRecords.reduce(0.0) { $0 + ($1.cachedEfficiency ?? 0) } / Double(allEfficiencyRecords.count)
            self.efficiencyAverage = unitSystem.efficiencyDisplayValue(
                from: rawAvg,
                metricFormat: metricEfficiencyFormat
            )
        } else {
            self.efficiencyAverage = 0
        }

        // Efficiency Y-range
        let allEfficiencyValues = allEfficiencyRecords.compactMap { $0.cachedEfficiency }.map {
            unitSystem.efficiencyDisplayValue(from: $0, metricFormat: metricEfficiencyFormat)
        }
        if let minVal = allEfficiencyValues.min(), let maxVal = allEfficiencyValues.max() {
            let minY = floor(minVal / 5) * 5
            let maxY = ceil(maxVal / 5) * 5
            self.efficiencyYRange = minY...max(maxY, minY + 5)
        } else {
            self.efficiencyYRange = 0...40
        }

        // Pre-compute Cost data from every record.
        self.costData = sorted.map { ChartDataPoint(id: $0.id, date: $0.date, value: $0.totalCost) }

        // Calculate cost average from ALL records
        if !sorted.isEmpty {
            self.costAverage = sorted.reduce(0.0) { $0 + $1.totalCost } / Double(sorted.count)
        } else {
            self.costAverage = 0
        }

        // Cost Y-range (use original data for accurate range)
        let allCostValues = sorted.map { $0.totalCost }
        if let minCost = allCostValues.min(), let maxCost = allCostValues.max() {
            let minY = floor(minCost / 10) * 10
            let maxY = ceil(maxCost / 10) * 10
            self.costYRange = minY...max(maxY, minY + 10)
        } else {
            self.costYRange = 0...100
        }

        // Pre-compute Price data from every record.
        self.priceData = sorted.map { ChartDataPoint(id: $0.id, date: $0.date, value: $0.pricePerFuelUnit) }

        // Calculate price average from ALL records
        if !sorted.isEmpty {
            self.priceAverage = sorted.reduce(0.0) { $0 + $1.pricePerFuelUnit } / Double(sorted.count)
        } else {
            self.priceAverage = 0
        }

        // Price Y-range (use original data for accurate range)
        let allPriceValues = sorted.map { $0.pricePerFuelUnit }
        if let minPrice = allPriceValues.min(), let maxPrice = allPriceValues.max() {
            let minY = floor(minPrice * 2) / 2
            let maxY = ceil(maxPrice * 2) / 2
            self.priceYRange = minY...max(maxY, minY + 0.5)
        } else {
            self.priceYRange = 0...5
        }
    }

    /// Average efficiency into date-ordered buckets for a smoother long-history trend.
    private static func createAveragedEfficiencyDataPoints(
        from records: [FuelingRecord],
        targetCount: Int,
        unitSystem: UnitSystem,
        metricEfficiencyFormat: MetricEfficiencyFormat
    ) -> [ChartDataPoint] {
        guard records.count > targetCount else {
            return records.compactMap { record in
                guard let efficiency = record.cachedEfficiency, efficiency > 0 else { return nil }
                return ChartDataPoint(
                    id: record.id,
                    date: record.date,
                    value: unitSystem.efficiencyDisplayValue(
                        from: efficiency,
                        metricFormat: metricEfficiencyFormat
                    )
                )
            }
        }

        var dataPoints: [ChartDataPoint] = []
        dataPoints.reserveCapacity(targetCount)

        let bucketSize = Double(records.count) / Double(targetCount)

        for index in 0..<targetCount {
            let startIndex = Int(Double(index) * bucketSize)
            let endIndex = min(Int(Double(index + 1) * bucketSize), records.count)

            guard startIndex < endIndex else { continue }

            var totalEfficiency = 0.0
            var efficiencyCount = 0

            for recordIndex in startIndex..<endIndex {
                if let efficiency = records[recordIndex].cachedEfficiency, efficiency > 0 {
                    totalEfficiency += efficiency
                    efficiencyCount += 1
                }
            }

            guard efficiencyCount > 0 else { continue }

            let averageEfficiency = totalEfficiency / Double(efficiencyCount)
            let middleIndex = startIndex + (endIndex - startIndex) / 2

            dataPoints.append(ChartDataPoint(
                id: UUID(),
                date: records[middleIndex].date,
                value: unitSystem.efficiencyDisplayValue(
                    from: averageEfficiency,
                    metricFormat: metricEfficiencyFormat
                )
            ))
        }

        return dataPoints
    }

}

struct ChartView: View {
    let records: [FuelingRecord]
    let unitSystem: UnitSystem
    let metricEfficiencyFormat: MetricEfficiencyFormat
    let invalidationKey: String

    @State private var selectedChart: ChartType = .efficiency
    @State private var chartData: PrecomputedChartData?

    init(
        records: [FuelingRecord],
        unitSystem: UnitSystem,
        metricEfficiencyFormat: MetricEfficiencyFormat = .defaultFormat,
        invalidationKey: String? = nil
    ) {
        self.records = records
        self.unitSystem = unitSystem
        self.metricEfficiencyFormat = metricEfficiencyFormat
        self.invalidationKey = invalidationKey ?? "\(records.count)"
    }

    enum ChartType: CaseIterable {
        case efficiency
        case cost
        case pricePerFuelUnit

        func label(
            for unitSystem: UnitSystem,
            metricEfficiencyFormat: MetricEfficiencyFormat
        ) -> String {
            switch self {
            case .efficiency:
                return unitSystem.efficiencyUnit(for: metricEfficiencyFormat)
            case .cost: return String(localized: "Cost")
            case .pricePerFuelUnit: return "$\(unitSystem.pricePerFuelShort)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Chart Type Picker
            Picker("Chart Type", selection: $selectedChart) {
                ForEach(ChartType.allCases, id: \.self) { type in
                    Text(type.label(
                        for: unitSystem,
                        metricEfficiencyFormat: metricEfficiencyFormat
                    ))
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)

            // Chart - use pre-computed data
            Group {
                if let data = chartData {
                    switch selectedChart {
                    case .efficiency:
                        EfficiencyChart(
                            data: data.efficiencyData,
                            average: data.efficiencyAverage,
                            yRange: data.efficiencyYRange,
                            showPoints: data.showPoints,
                            unitSystem: unitSystem,
                            metricEfficiencyFormat: metricEfficiencyFormat
                        )
                    case .cost:
                        CostChart(data: data.costData, average: data.costAverage, yRange: data.costYRange, showPoints: data.showPoints)
                    case .pricePerFuelUnit:
                        PricePerFuelUnitChart(data: data.priceData, average: data.priceAverage, yRange: data.priceYRange, showPoints: data.showPoints, unitSystem: unitSystem)
                    }
                } else {
                    ProgressView()
                        .frame(height: 200)
                }
            }
            .padding()
            .cardStyle()
        }
        .onAppear {
            prepareChartData()
        }
        .onChange(of: invalidationKey) { _, _ in
            prepareChartData()
        }
        .onChange(of: unitSystem) { _, _ in
            prepareChartData()
        }
        .onChange(of: metricEfficiencyFormat) { _, _ in
            prepareChartData()
        }
    }

    private func prepareChartData() {
        // Compute data once and cache it
        chartData = PrecomputedChartData(
            records: records,
            unitSystem: unitSystem,
            metricEfficiencyFormat: metricEfficiencyFormat
        )
    }
}

struct EfficiencyChart: View {
    let data: [ChartDataPoint]
    let average: Double
    let yRange: ClosedRange<Double>
    let showPoints: Bool
    let unitSystem: UnitSystem
    let metricEfficiencyFormat: MetricEfficiencyFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(unitSystem.efficiencyName(for: metricEfficiencyFormat))
                    .font(.appSubheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Avg: \(average.formatted(.number.precision(.fractionLength(1)))) \(unitSystem.efficiencyUnit(for: metricEfficiencyFormat))")
                    .font(.appCaption)
                    .foregroundColor(.purple)
            }

            Chart {
                ForEach(data) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(unitSystem.efficiencyUnit(for: metricEfficiencyFormat), point.value)
                    )
                    .foregroundStyle(Color.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Min", yRange.lowerBound),
                        yEnd: .value(unitSystem.efficiencyUnit(for: metricEfficiencyFormat), point.value)
                    )
                    .foregroundStyle(LinearGradient.efficiencyChartFill)

                    // Only show points if there aren't too many
                    if showPoints {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value(unitSystem.efficiencyUnit(for: metricEfficiencyFormat), point.value)
                        )
                        .foregroundStyle(.purple)
                        .symbolSize(40)
                    }
                }

                // Average line
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(.purple.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
            .chartYScale(domain: yRange)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day().year(.twoDigits))
                }
            }
        }
    }
}

struct CostChart: View {
    let data: [ChartDataPoint]
    let average: Double
    let yRange: ClosedRange<Double>
    let showPoints: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cost per Fill-up")
                    .font(.appSubheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Avg: \(average.currencyFormatted)")
                    .font(.appCaption)
                    .foregroundColor(.orange)
            }

            Chart {
                ForEach(data) { point in
                    BarMark(
                        x: .value("Date", point.date),
                        yStart: .value("Min", yRange.lowerBound),
                        yEnd: .value("Cost", point.value)
                    )
                    .foregroundStyle(Color.orange)
                    .cornerRadius(4)
                }

                // Average line
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(.orange.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
            .chartYScale(domain: yRange)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let cost = value.as(Double.self) {
                            Text(cost.currencyFormatted)
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day().year(.twoDigits))
                }
            }
        }
    }
}

struct PricePerFuelUnitChart: View {
    let data: [ChartDataPoint]
    let average: Double
    let yRange: ClosedRange<Double>
    let showPoints: Bool
    let unitSystem: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(unitSystem.pricePerFuelLabel)
                    .font(.appSubheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Avg: \(average.currencyFormatted)")
                    .font(.appCaption)
                    .foregroundColor(.green)
            }

            Chart {
                ForEach(data) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Price", point.value)
                    )
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Min", yRange.lowerBound),
                        yEnd: .value("Price", point.value)
                    )
                    .foregroundStyle(LinearGradient.priceChartFill)

                    // Only show points if there aren't too many
                    if showPoints {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Price", point.value)
                        )
                        .foregroundStyle(.green)
                        .symbolSize(40)
                    }
                }

                // Average line
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(.green.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
            .chartYScale(domain: yRange)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let price = value.as(Double.self) {
                            Text(price.currencyFormatted)
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day().year(.twoDigits))
                }
            }
        }
    }
}

#Preview {
    ChartView(records: [], unitSystem: .imperial)
        .padding()
}
