import Foundation
import SwiftUI

/// ViewModel for calculating and managing vehicle statistics
@Observable
class StatisticsViewModel {
    private var records: [FuelingRecord]

    init(records: [FuelingRecord]) {
        self.records = records
    }

    func updateRecords(_ records: [FuelingRecord]) {
        self.records = records
    }

    // MARK: - Basic Statistics

    var totalSpent: Double {
        records.reduce(0) { $0 + $1.totalCost }
    }

    var totalMiles: Double {
        records.reduce(0) { $0 + $1.milesDriven }
    }

    var totalGallons: Double {
        records.reduce(0) { $0 + $1.gallons }
    }

    var totalFillUps: Int {
        records.count
    }

    // MARK: - Averages

    var averageMPG: Double {
        // Exclude partial fill-ups and initial records (baseline records have no valid MPG)
        let validRecords = records.filter { !$0.isPartialFillUp && !$0.isInitialRecord }
        guard !validRecords.isEmpty else { return 0 }

        let totalValidMiles = validRecords.reduce(0) { $0 + $1.milesDriven }
        let totalValidGallons = validRecords.reduce(0) { $0 + $1.gallons }
        guard totalValidGallons > 0 else { return 0 }
        return totalValidMiles / totalValidGallons
    }

    var averageCostPerMile: Double {
        guard totalMiles > 0 else { return 0 }
        return totalSpent / totalMiles
    }

    var averageFillUpCost: Double {
        guard !records.isEmpty else { return 0 }
        return totalSpent / Double(records.count)
    }

    var averagePricePerGallon: Double {
        guard !records.isEmpty else { return 0 }
        return records.reduce(0) { $0 + $1.pricePerGallon } / Double(records.count)
    }

    var averageGallonsPerFillUp: Double {
        guard !records.isEmpty else { return 0 }
        return totalGallons / Double(records.count)
    }

    // MARK: - Time-based Statistics

    var lastFillUpDate: Date? {
        records.max(by: { $0.date < $1.date })?.date
    }

    var daysSinceLastFillUp: Int? {
        guard let lastDate = lastFillUpDate else { return nil }
        return Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day
    }

    // MARK: - Monthly Statistics

    func monthlySpending(for month: Date) -> Double {
        records.records(forMonth: month).totalCost
    }

    func monthlyMiles(for month: Date) -> Double {
        records.records(forMonth: month).totalMiles
    }

    func monthlyGallons(for month: Date) -> Double {
        records.records(forMonth: month).totalGallons
    }

    // MARK: - Best/Worst Statistics

    var bestMPG: Double? {
        records.filter { !$0.isPartialFillUp && !$0.isInitialRecord }.max(by: { $0.mpg < $1.mpg })?.mpg
    }

    var worstMPG: Double? {
        records.filter { !$0.isPartialFillUp && !$0.isInitialRecord }.min(by: { $0.mpg < $1.mpg })?.mpg
    }

    var highestPricePerGallon: Double? {
        records.max(by: { $0.pricePerGallon < $1.pricePerGallon })?.pricePerGallon
    }

    var lowestPricePerGallon: Double? {
        records.min(by: { $0.pricePerGallon < $1.pricePerGallon })?.pricePerGallon
    }

    var mostExpensiveFillUp: FuelingRecord? {
        records.max(by: { $0.totalCost < $1.totalCost })
    }

    var cheapestFillUp: FuelingRecord? {
        records.min(by: { $0.totalCost < $1.totalCost })
    }

    // MARK: - Trends

    /// Calculate the trend in MPG over the last N records
    func mpgTrend(lastN: Int = 5) -> TrendDirection {
        let recentRecords = Array(records.filter { !$0.isPartialFillUp && !$0.isInitialRecord }.prefix(lastN))
        guard recentRecords.count >= 2 else { return .stable }

        let recentAvg = recentRecords.reduce(0) { $0 + $1.mpg } / Double(recentRecords.count)
        let overallAvg = averageMPG

        let difference = recentAvg - overallAvg
        let threshold = overallAvg * 0.05 // 5% threshold

        if difference > threshold {
            return .improving
        } else if difference < -threshold {
            return .declining
        }
        return .stable
    }

    /// Calculate the trend in cost per gallon over the last N records
    func priceTrend(lastN: Int = 5) -> TrendDirection {
        let recentRecords = Array(records.prefix(lastN))
        guard recentRecords.count >= 2 else { return .stable }

        let recentAvg = recentRecords.reduce(0) { $0 + $1.pricePerGallon } / Double(recentRecords.count)
        let overallAvg = averagePricePerGallon

        let difference = recentAvg - overallAvg
        let threshold = overallAvg * 0.05

        if difference > threshold {
            return .increasing
        } else if difference < -threshold {
            return .decreasing
        }
        return .stable
    }

    enum TrendDirection {
        case improving
        case declining
        case stable
        case increasing
        case decreasing

        var icon: String {
            switch self {
            case .improving, .decreasing:
                return "arrow.up.right"
            case .declining, .increasing:
                return "arrow.down.right"
            case .stable:
                return "arrow.right"
            }
        }

        var color: Color {
            switch self {
            case .improving, .decreasing:
                return .green
            case .declining, .increasing:
                return .red
            case .stable:
                return .secondary
            }
        }
    }

    // MARK: - Chart Data

    struct ChartDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let label: String
    }

    func mpgChartData() -> [ChartDataPoint] {
        records.filter { !$0.isPartialFillUp && !$0.isInitialRecord }
            .sorted { $0.date < $1.date }
            .map { ChartDataPoint(date: $0.date, value: $0.mpg, label: "\($0.mpg.formatted(decimals: 1)) MPG") }
    }

    func costChartData() -> [ChartDataPoint] {
        records.sorted { $0.date < $1.date }
            .map { ChartDataPoint(date: $0.date, value: $0.totalCost, label: $0.totalCost.currencyFormatted) }
    }

    func priceChartData() -> [ChartDataPoint] {
        records.sorted { $0.date < $1.date }
            .map { ChartDataPoint(date: $0.date, value: $0.pricePerGallon, label: $0.pricePerGallon.currencyFormatted) }
    }
}

