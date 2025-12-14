import Foundation
import SwiftData

@Model
final class Vehicle {
    var id: UUID = UUID()
    var name: String = ""
    var make: String?
    var model: String?
    var year: Int?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \FuelingRecord.vehicle)
    var fuelingRecords: [FuelingRecord]?

    // MARK: - Cached Statistics (for performance)
    // These are pre-computed and stored to avoid recalculating on every view render
    var cachedTotalSpent: Double?
    var cachedTotalMiles: Double?
    var cachedTotalGallons: Double?
    var cachedAverageMPG: Double?
    var cachedAverageCostPerMile: Double?
    var cachedAverageFillUpCost: Double?
    var cachedAveragePricePerGallon: Double?
    var cachedBestMPG: Double?
    var cachedWorstMPG: Double?
    var cachedHighestPricePerGallon: Double?
    var cachedLowestPricePerGallon: Double?
    var cachedRecordCount: Int?
    var cacheLastUpdated: Date?

    init(
        id: UUID = UUID(),
        name: String,
        make: String? = nil,
        model: String? = nil,
        year: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.make = make
        self.model = model
        self.year = year
        self.createdAt = createdAt
    }

    var displayName: String {
        if let make = make, let model = model {
            if let year = year {
                return "\(year) \(make) \(model)"
            }
            return "\(make) \(model)"
        }
        return name
    }

    var sortedRecords: [FuelingRecord] {
        (fuelingRecords ?? []).sorted { $0.date > $1.date }
    }

    var lastRecord: FuelingRecord? {
        sortedRecords.first
    }

    // MARK: - Cache Status

    /// Check if cache needs to be rebuilt (no cache or records changed)
    var needsCacheRebuild: Bool {
        guard cacheLastUpdated != nil else { return true }
        guard let cachedCount = cachedRecordCount else { return true }
        return cachedCount != (fuelingRecords?.count ?? 0)
    }

    /// Invalidate the cache (call before full recalculation)
    func invalidateCache() {
        cachedTotalSpent = nil
        cachedTotalMiles = nil
        cachedTotalGallons = nil
        cachedAverageMPG = nil
        cachedAverageCostPerMile = nil
        cachedAverageFillUpCost = nil
        cachedAveragePricePerGallon = nil
        cachedBestMPG = nil
        cachedWorstMPG = nil
        cachedHighestPricePerGallon = nil
        cachedLowestPricePerGallon = nil
        cachedRecordCount = nil
        cacheLastUpdated = nil
    }
}

