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

    /// Maximum number of points to display for performance
    static let maxDisplayPoints = 100

    init(records: [FuelingRecord], unitSystem: UnitSystem) {
        self.unitSystem = unitSystem

        // Sort once
        let sorted = records.sorted { $0.date < $1.date }

        // Determine if we should show individual points (performance optimization)
        self.showPoints = sorted.count <= Self.maxDisplayPoints

        // Pre-compute efficiency data with bucket averaging
        let allEfficiencyRecords = sorted.filter { $0.cachedEfficiency != nil && $0.cachedEfficiency! > 0 }
        if allEfficiencyRecords.count > Self.maxDisplayPoints {
            self.efficiencyData = Self.createAveragedDataPoints(
                from: allEfficiencyRecords,
                targetCount: Self.maxDisplayPoints,
                valueExtractor: { unitSystem.efficiencyDisplayValue(from: $0.cachedEfficiency ?? 0) }
            )
        } else {
            self.efficiencyData = allEfficiencyRecords.map {
                ChartDataPoint(id: $0.id, date: $0.date, value: unitSystem.efficiencyDisplayValue(from: $0.cachedEfficiency!))
            }
        }

        // Calculate efficiency average from ALL valid records
        if !allEfficiencyRecords.isEmpty {
            let rawAvg = allEfficiencyRecords.reduce(0.0) { $0 + ($1.cachedEfficiency ?? 0) } / Double(allEfficiencyRecords.count)
            self.efficiencyAverage = unitSystem.efficiencyDisplayValue(from: rawAvg)
        } else {
            self.efficiencyAverage = 0
        }

        // Efficiency Y-range
        let allEfficiencyValues = allEfficiencyRecords.compactMap { $0.cachedEfficiency }.map { unitSystem.efficiencyDisplayValue(from: $0) }
        if let minVal = allEfficiencyValues.min(), let maxVal = allEfficiencyValues.max() {
            let minY = floor(minVal / 5) * 5
            let maxY = ceil(maxVal / 5) * 5
            self.efficiencyYRange = minY...max(maxY, minY + 5)
        } else {
            self.efficiencyYRange = 0...40
        }

        // Pre-compute Cost data with bucket averaging
        if sorted.count > Self.maxDisplayPoints {
            self.costData = Self.createAveragedDataPoints(
                from: sorted,
                targetCount: Self.maxDisplayPoints,
                valueExtractor: { $0.totalCost }
            )
        } else {
            self.costData = sorted.map { ChartDataPoint(id: $0.id, date: $0.date, value: $0.totalCost) }
        }

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

        // Pre-compute Price data with bucket averaging
        if sorted.count > Self.maxDisplayPoints {
            self.priceData = Self.createAveragedDataPoints(
                from: sorted,
                targetCount: Self.maxDisplayPoints,
                valueExtractor: { $0.pricePerFuelUnit }
            )
        } else {
            self.priceData = sorted.map { ChartDataPoint(id: $0.id, date: $0.date, value: $0.pricePerFuelUnit) }
        }

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

    /// Create averaged data points by dividing records into buckets and averaging each bucket
    /// This produces a smoother trend line that better represents the underlying data
    private static func createAveragedDataPoints(
        from records: [FuelingRecord],
        targetCount: Int,
        valueExtractor: (FuelingRecord) -> Double
    ) -> [ChartDataPoint] {
        guard records.count > targetCount else {
            return records.map { ChartDataPoint(id: $0.id, date: $0.date, value: valueExtractor($0)) }
        }

        var dataPoints: [ChartDataPoint] = []
        let bucketSize = Double(records.count) / Double(targetCount)

        for i in 0..<targetCount {
            let startIndex = Int(Double(i) * bucketSize)
            let endIndex = min(Int(Double(i + 1) * bucketSize), records.count)

            guard startIndex < endIndex else { continue }

            let bucketRecords = Array(records[startIndex..<endIndex])

            // Calculate average value for this bucket
            let avgValue = bucketRecords.reduce(0.0) { $0 + valueExtractor($1) } / Double(bucketRecords.count)

            // Use the middle record's date as the representative date
            let middleIndex = bucketRecords.count / 2
            let representativeDate = bucketRecords[middleIndex].date

            dataPoints.append(ChartDataPoint(
                id: UUID(),
                date: representativeDate,
                value: avgValue
            ))
        }

        return dataPoints
    }
}

struct ChartView: View {
    let records: [FuelingRecord]
    let unitSystem: UnitSystem

    @State private var selectedChart: ChartType = .efficiency
    @State private var chartData: PrecomputedChartData?

    enum ChartType: CaseIterable {
        case efficiency
        case cost
        case pricePerFuelUnit

        func label(for unitSystem: UnitSystem) -> String {
            switch self {
            case .efficiency: return unitSystem.efficiencyUnit
            case .cost: return "Cost"
            case .pricePerFuelUnit: return "$\(unitSystem.pricePerFuelShort)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Chart Type Picker
            Picker("Chart Type", selection: $selectedChart) {
                ForEach(ChartType.allCases, id: \.self) { type in
                    Text(type.label(for: unitSystem))
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)

            // Chart - use pre-computed data
            Group {
                if let data = chartData {
                    switch selectedChart {
                    case .efficiency:
                        EfficiencyChart(data: data.efficiencyData, average: data.efficiencyAverage, yRange: data.efficiencyYRange, showPoints: data.showPoints, unitSystem: unitSystem)
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
        .onChange(of: records.count) { _, _ in
            prepareChartData()
        }
    }

    private func prepareChartData() {
        // Compute data once and cache it
        chartData = PrecomputedChartData(records: records, unitSystem: unitSystem)
    }
}

struct EfficiencyChart: View {
    let data: [ChartDataPoint]
    let average: Double
    let yRange: ClosedRange<Double>
    let showPoints: Bool
    let unitSystem: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(unitSystem.efficiencyName)
                    .font(.appSubheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Avg: \(average.formatted(.number.precision(.fractionLength(1)))) \(unitSystem.efficiencyUnit)")
                    .font(.appCaption)
                    .foregroundColor(.purple)
            }

            Chart {
                ForEach(data) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(unitSystem.efficiencyUnit, point.value)
                    )
                    .foregroundStyle(Color.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Min", yRange.lowerBound),
                        yEnd: .value(unitSystem.efficiencyUnit, point.value)
                    )
                    .foregroundStyle(LinearGradient.efficiencyChartFill)

                    // Only show points if there aren't too many
                    if showPoints {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value(unitSystem.efficiencyUnit, point.value)
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
