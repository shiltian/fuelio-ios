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
    let mpgData: [ChartDataPoint]
    let mpgAverage: Double
    let mpgYRange: ClosedRange<Double>

    let costData: [ChartDataPoint]
    let costAverage: Double
    let costYRange: ClosedRange<Double>

    let priceData: [ChartDataPoint]
    let priceAverage: Double
    let priceYRange: ClosedRange<Double>

    let showPoints: Bool  // Only show points if data count is reasonable

    /// Maximum number of points to display for performance
    static let maxDisplayPoints = 100

    init(records: [FuelingRecord]) {
        // Sort once
        let sorted = records.sorted { $0.date < $1.date }

        // Determine if we should show individual points (performance optimization)
        self.showPoints = sorted.count <= Self.maxDisplayPoints

        // Pre-compute MPG data with bucket averaging
        let allMPGRecords = sorted.filter { $0.cachedMPG != nil && $0.cachedMPG! > 0 }
        if allMPGRecords.count > Self.maxDisplayPoints {
            self.mpgData = Self.createAveragedDataPoints(
                from: allMPGRecords,
                targetCount: Self.maxDisplayPoints,
                valueExtractor: { $0.cachedMPG ?? 0 }
            )
        } else {
            self.mpgData = allMPGRecords.map { ChartDataPoint(id: $0.id, date: $0.date, value: $0.cachedMPG!) }
        }

        // Calculate MPG average from ALL valid records
        if !allMPGRecords.isEmpty {
            self.mpgAverage = allMPGRecords.reduce(0.0) { $0 + ($1.cachedMPG ?? 0) } / Double(allMPGRecords.count)
        } else {
            self.mpgAverage = 0
        }

        // MPG Y-range (use original data for accurate range)
        let allMPGValues = allMPGRecords.compactMap { $0.cachedMPG }
        if let minMPG = allMPGValues.min(), let maxMPG = allMPGValues.max() {
            let minY = floor(minMPG / 5) * 5
            let maxY = ceil(maxMPG / 5) * 5
            self.mpgYRange = minY...max(maxY, minY + 5)
        } else {
            self.mpgYRange = 0...40
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
                valueExtractor: { $0.pricePerGallon }
            )
        } else {
            self.priceData = sorted.map { ChartDataPoint(id: $0.id, date: $0.date, value: $0.pricePerGallon) }
        }

        // Calculate price average from ALL records
        if !sorted.isEmpty {
            self.priceAverage = sorted.reduce(0.0) { $0 + $1.pricePerGallon } / Double(sorted.count)
        } else {
            self.priceAverage = 0
        }

        // Price Y-range (use original data for accurate range)
        let allPriceValues = sorted.map { $0.pricePerGallon }
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

    @State private var selectedChart: ChartType = .mpg
    @State private var chartData: PrecomputedChartData?

    enum ChartType: String, CaseIterable {
        case mpg = "MPG"
        case cost = "Cost"
        case pricePerGallon = "$/Gallon"
    }

    var body: some View {
        VStack(spacing: 12) {
            // Chart Type Picker
            Picker("Chart Type", selection: $selectedChart) {
                ForEach(ChartType.allCases, id: \.self) { type in
                    Text(type.rawValue)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)

            // Chart - use pre-computed data
            Group {
                if let data = chartData {
                    switch selectedChart {
                    case .mpg:
                        MPGChart(data: data.mpgData, average: data.mpgAverage, yRange: data.mpgYRange, showPoints: data.showPoints)
                    case .cost:
                        CostChart(data: data.costData, average: data.costAverage, yRange: data.costYRange, showPoints: data.showPoints)
                    case .pricePerGallon:
                        PricePerGallonChart(data: data.priceData, average: data.priceAverage, yRange: data.priceYRange, showPoints: data.showPoints)
                    }
                } else {
                    ProgressView()
                        .frame(height: 200)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
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
        chartData = PrecomputedChartData(records: records)
    }
}

struct MPGChart: View {
    let data: [ChartDataPoint]
    let average: Double
    let yRange: ClosedRange<Double>
    let showPoints: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Miles Per Gallon")
                    .font(.custom("Avenir Next", size: 14))
                    .foregroundColor(.secondary)

                Spacer()

                Text("Avg: \(average.formatted(.number.precision(.fractionLength(1)))) MPG")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.purple)
            }

            Chart {
                ForEach(data) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("MPG", point.value)
                    )
                    .foregroundStyle(Color.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Min", yRange.lowerBound),
                        yEnd: .value("MPG", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .purple.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Only show points if there aren't too many
                    if showPoints {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("MPG", point.value)
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
                    .font(.custom("Avenir Next", size: 14))
                    .foregroundColor(.secondary)

                Spacer()

                Text("Avg: \(average.currencyFormatted)")
                    .font(.custom("Avenir Next", size: 12))
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

struct PricePerGallonChart: View {
    let data: [ChartDataPoint]
    let average: Double
    let yRange: ClosedRange<Double>
    let showPoints: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Price per Gallon")
                    .font(.custom("Avenir Next", size: 14))
                    .foregroundColor(.secondary)

                Spacer()

                Text("Avg: \(average.currencyFormatted)")
                    .font(.custom("Avenir Next", size: 12))
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
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green.opacity(0.3), .green.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

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
    ChartView(records: [])
        .padding()
}

