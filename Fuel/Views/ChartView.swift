import SwiftUI
import Charts

struct ChartView: View {
    let records: [FuelingRecord]

    @State private var selectedChart: ChartType = .mpg

    enum ChartType: String, CaseIterable {
        case mpg = "MPG"
        case cost = "Cost"
        case pricePerGallon = "$/Gallon"
    }

    private var sortedRecords: [FuelingRecord] {
        records.sorted { $0.date < $1.date }
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

            // Chart
            Group {
                switch selectedChart {
                case .mpg:
                    MPGChart(records: sortedRecords)
                case .cost:
                    CostChart(records: sortedRecords)
                case .pricePerGallon:
                    PricePerGallonChart(records: sortedRecords)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
    }
}

struct MPGChart: View {
    let records: [FuelingRecord]

    /// Records that can have accurate MPG calculated:
    /// - Must be a full fill-up
    /// - Previous record must also be a full fill-up (so we know the tank was full)
    private var validMPGRecords: [FuelingRecord] {
        let sortedByDate = records.sorted { $0.date < $1.date }
        var result: [FuelingRecord] = []

        for (index, record) in sortedByDate.enumerated() {
            // Skip partial fill-ups
            guard !record.isPartialFillUp else { continue }

            // Skip if this is the first record (no previous miles to compare)
            guard index > 0 else { continue }

            // Skip if the previous record was a partial fill-up
            // (we can't accurately calculate MPG without knowing the tank was full)
            let previousRecord = sortedByDate[index - 1]
            guard !previousRecord.isPartialFillUp else { continue }

            result.append(record)
        }

        return result
    }

    /// Get the previous miles for a given record (from the previous full fill-up)
    private func previousMiles(for record: FuelingRecord) -> Double {
        let sortedByDate = records.sorted { $0.date < $1.date }
        guard let index = sortedByDate.firstIndex(where: { $0.id == record.id }),
              index > 0 else {
            return 0
        }
        // Find the previous full fill-up
        for i in stride(from: index - 1, through: 0, by: -1) {
            if !sortedByDate[i].isPartialFillUp {
                return sortedByDate[i].currentMiles
            }
        }
        return 0
    }

    private var averageMPG: Double {
        guard !validMPGRecords.isEmpty else { return 0 }
        return validMPGRecords.reduce(0) { $0 + $1.mpg(previousMiles: previousMiles(for: $1)) } / Double(validMPGRecords.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Miles Per Gallon")
                    .font(.custom("Avenir Next", size: 14))
                    .foregroundColor(.secondary)

                Spacer()

                Text("Avg: \(averageMPG.formatted(.number.precision(.fractionLength(1)))) MPG")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.purple)
            }

            Chart {
                ForEach(validMPGRecords, id: \.id) { record in
                    let mpg = record.mpg(previousMiles: previousMiles(for: record))
                    LineMark(
                        x: .value("Date", record.date),
                        y: .value("MPG", mpg)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    AreaMark(
                        x: .value("Date", record.date),
                        y: .value("MPG", mpg)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .purple.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    PointMark(
                        x: .value("Date", record.date),
                        y: .value("MPG", mpg)
                    )
                    .foregroundStyle(.purple)
                    .symbolSize(40)
                }

                // Average line
                RuleMark(y: .value("Average", averageMPG))
                    .foregroundStyle(.purple.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
        }
    }
}

struct CostChart: View {
    let records: [FuelingRecord]

    private var averageCost: Double {
        guard !records.isEmpty else { return 0 }
        return records.reduce(0) { $0 + $1.totalCost } / Double(records.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cost per Fill-up")
                    .font(.custom("Avenir Next", size: 14))
                    .foregroundColor(.secondary)

                Spacer()

                Text("Avg: \(averageCost.currencyFormatted)")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.orange)
            }

            Chart {
                ForEach(records, id: \.id) { record in
                    BarMark(
                        x: .value("Date", record.date),
                        y: .value("Cost", record.totalCost)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(4)
                }

                // Average line
                RuleMark(y: .value("Average", averageCost))
                    .foregroundStyle(.orange.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
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
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
        }
    }
}

struct PricePerGallonChart: View {
    let records: [FuelingRecord]

    private var averagePrice: Double {
        guard !records.isEmpty else { return 0 }
        return records.reduce(0) { $0 + $1.pricePerGallon } / Double(records.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Price per Gallon")
                    .font(.custom("Avenir Next", size: 14))
                    .foregroundColor(.secondary)

                Spacer()

                Text("Avg: \(averagePrice.currencyFormatted)")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.green)
            }

            Chart {
                ForEach(records, id: \.id) { record in
                    LineMark(
                        x: .value("Date", record.date),
                        y: .value("Price", record.pricePerGallon)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    AreaMark(
                        x: .value("Date", record.date),
                        y: .value("Price", record.pricePerGallon)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green.opacity(0.3), .green.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    PointMark(
                        x: .value("Date", record.date),
                        y: .value("Price", record.pricePerGallon)
                    )
                    .foregroundStyle(.green)
                    .symbolSize(40)
                }

                // Average line
                RuleMark(y: .value("Average", averagePrice))
                    .foregroundStyle(.green.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
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
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
        }
    }
}

#Preview {
    ChartView(records: [])
        .padding()
}

