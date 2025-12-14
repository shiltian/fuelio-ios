import Foundation
import SwiftData

/// Service for efficiently computing and caching vehicle statistics
/// Reduces complexity from O(n² log n) to O(n log n) by computing everything in a single pass
final class StatisticsCacheService {

    // MARK: - Full Recalculation

    /// Recalculate all statistics for a vehicle in a single efficient pass
    /// Time complexity: O(n log n) where n = number of records
    /// - Parameter vehicle: The vehicle to recalculate statistics for
    static func recalculateAllStatistics(for vehicle: Vehicle) {
        let records = vehicle.fuelingRecords ?? []

        guard !records.isEmpty else {
            vehicle.invalidateCache()
            vehicle.cachedRecordCount = 0
            vehicle.cacheLastUpdated = Date()
            return
        }

        // Sort once - O(n log n)
        let sortedByDate = records.sorted { $0.date < $1.date }

        // Single pass to compute all per-record cached values and aggregate statistics - O(n)
        var totalSpent: Double = 0
        var totalMiles: Double = 0
        var totalGallons: Double = 0
        var totalPricePerGallon: Double = 0

        var fullFillUpMiles: Double = 0
        var fullFillUpGallons: Double = 0

        var bestMPG: Double = 0
        var worstMPG: Double = Double.greatestFiniteMagnitude
        var highestPrice: Double = 0
        var lowestPrice: Double = Double.greatestFiniteMagnitude

        var hasValidMPG = false
        var previousMiles: Double = 0
        var previousWasFullFillUp = false

        for (index, record) in sortedByDate.enumerated() {
            // Cache previous miles for this record
            record.cachedPreviousMiles = previousMiles

            // Calculate miles driven
            let milesDriven: Double
            if previousMiles > 0 {
                milesDriven = record.currentMiles - previousMiles
                record.cachedMilesDriven = milesDriven
            } else {
                milesDriven = 0
                record.cachedMilesDriven = 0
            }

            // Calculate MPG (only for full fill-ups where previous was also full)
            // Partial: didn't fill tank completely (affects next record's MPG baseline)
            // Reset: missed fueling(s) before this record (can't trust miles driven for this record)
            let mpg: Double
            if record.isFullFillUp && previousWasFullFillUp && milesDriven > 0 && record.gallons > 0 {
                mpg = milesDriven / record.gallons
                record.cachedMPG = mpg

                // Track best/worst MPG
                hasValidMPG = true
                if mpg > bestMPG { bestMPG = mpg }
                if mpg < worstMPG { worstMPG = mpg }

                // Accumulate for average MPG calculation
                fullFillUpMiles += milesDriven
                fullFillUpGallons += record.gallons
            } else {
                mpg = 0
                record.cachedMPG = nil
            }

            // Calculate cost per mile
            if milesDriven > 0 {
                record.cachedCostPerMile = record.totalCost / milesDriven
            } else {
                record.cachedCostPerMile = nil
            }

            // Accumulate totals
            totalSpent += record.totalCost
            totalMiles += milesDriven
            totalGallons += record.gallons
            totalPricePerGallon += record.pricePerGallon

            // Track price extremes
            if record.pricePerGallon > highestPrice { highestPrice = record.pricePerGallon }
            if record.pricePerGallon < lowestPrice { lowestPrice = record.pricePerGallon }

            // Update state for next iteration
            previousMiles = record.currentMiles
            previousWasFullFillUp = record.isFullFillUp || index == 0
        }

        // Store aggregated statistics on the vehicle
        vehicle.cachedTotalSpent = totalSpent
        vehicle.cachedTotalMiles = totalMiles
        vehicle.cachedTotalGallons = totalGallons
        vehicle.cachedRecordCount = records.count

        // Average MPG from full fill-ups only (more accurate)
        if fullFillUpGallons > 0 {
            vehicle.cachedAverageMPG = fullFillUpMiles / fullFillUpGallons
        } else if totalGallons > 0 {
            // Fallback to all records if no full fill-ups
            vehicle.cachedAverageMPG = totalMiles / totalGallons
        } else {
            vehicle.cachedAverageMPG = 0
        }

        // Average cost per mile
        if totalMiles > 0 {
            vehicle.cachedAverageCostPerMile = totalSpent / totalMiles
        } else {
            vehicle.cachedAverageCostPerMile = 0
        }

        // Average fill-up cost
        vehicle.cachedAverageFillUpCost = totalSpent / Double(records.count)

        // Average price per gallon
        vehicle.cachedAveragePricePerGallon = totalPricePerGallon / Double(records.count)

        // Best/worst MPG
        vehicle.cachedBestMPG = hasValidMPG ? bestMPG : nil
        vehicle.cachedWorstMPG = hasValidMPG && worstMPG != Double.greatestFiniteMagnitude ? worstMPG : nil

        // Price extremes
        vehicle.cachedHighestPricePerGallon = highestPrice > 0 ? highestPrice : nil
        vehicle.cachedLowestPricePerGallon = lowestPrice != Double.greatestFiniteMagnitude ? lowestPrice : nil

        vehicle.cacheLastUpdated = Date()
    }

    // MARK: - Incremental Updates

    /// Update statistics after adding a new record
    /// If the record is the most recent, this is O(1). Otherwise, triggers full recalculation.
    static func updateForNewRecord(_ record: FuelingRecord, vehicle: Vehicle) {
        let records = vehicle.fuelingRecords ?? []

        // If this is the first record or records are empty, do full calculation
        guard records.count > 1 else {
            recalculateAllStatistics(for: vehicle)
            return
        }

        // Check if this record is the most recent by date
        let sortedByDate = records.sorted { $0.date < $1.date }
        let isLatestRecord = sortedByDate.last?.id == record.id

        if isLatestRecord {
            // Incremental update - O(1)
            incrementalAddLatestRecord(record, to: vehicle, sortedRecords: sortedByDate)
        } else {
            // Record inserted in the middle - need to recalculate from that point
            // For simplicity, just do a full recalculation
            recalculateAllStatistics(for: vehicle)
        }
    }

    /// Incremental update when adding the latest (most recent) record
    private static func incrementalAddLatestRecord(_ record: FuelingRecord, to vehicle: Vehicle, sortedRecords: [FuelingRecord]) {
        // Get the previous record
        let previousIndex = sortedRecords.count - 2
        guard previousIndex >= 0 else {
            recalculateAllStatistics(for: vehicle)
            return
        }

        let previousRecord = sortedRecords[previousIndex]
        let previousMiles = previousRecord.currentMiles

        // Cache values for the new record
        record.cachedPreviousMiles = previousMiles

        let milesDriven = record.currentMiles - previousMiles
        record.cachedMilesDriven = milesDriven > 0 ? milesDriven : 0

        // Calculate MPG if applicable (only for full fill-ups where previous was also full)
        if record.isFullFillUp && previousRecord.isFullFillUp && milesDriven > 0 && record.gallons > 0 {
            let mpg = milesDriven / record.gallons
            record.cachedMPG = mpg

            // Update best/worst MPG
            if let currentBest = vehicle.cachedBestMPG {
                if mpg > currentBest { vehicle.cachedBestMPG = mpg }
            } else {
                vehicle.cachedBestMPG = mpg
            }

            if let currentWorst = vehicle.cachedWorstMPG {
                if mpg < currentWorst { vehicle.cachedWorstMPG = mpg }
            } else {
                vehicle.cachedWorstMPG = mpg
            }
        } else {
            record.cachedMPG = nil
        }

        // Calculate cost per mile
        if milesDriven > 0 {
            record.cachedCostPerMile = record.totalCost / milesDriven
        } else {
            record.cachedCostPerMile = nil
        }

        // Update aggregate totals
        vehicle.cachedTotalSpent = (vehicle.cachedTotalSpent ?? 0) + record.totalCost
        vehicle.cachedTotalMiles = (vehicle.cachedTotalMiles ?? 0) + (milesDriven > 0 ? milesDriven : 0)
        vehicle.cachedTotalGallons = (vehicle.cachedTotalGallons ?? 0) + record.gallons

        let newCount = (vehicle.cachedRecordCount ?? 0) + 1
        vehicle.cachedRecordCount = newCount

        // Recalculate averages
        if let totalSpent = vehicle.cachedTotalSpent {
            vehicle.cachedAverageFillUpCost = totalSpent / Double(newCount)
        }

        if let totalMiles = vehicle.cachedTotalMiles, totalMiles > 0, let totalSpent = vehicle.cachedTotalSpent {
            vehicle.cachedAverageCostPerMile = totalSpent / totalMiles
        }

        // For average MPG and price, it's easier to just recalculate
        // (they depend on specific subsets and would require tracking additional state)
        recalculateAverages(for: vehicle)

        // Update price extremes
        if let currentHighest = vehicle.cachedHighestPricePerGallon {
            if record.pricePerGallon > currentHighest {
                vehicle.cachedHighestPricePerGallon = record.pricePerGallon
            }
        } else {
            vehicle.cachedHighestPricePerGallon = record.pricePerGallon
        }

        if let currentLowest = vehicle.cachedLowestPricePerGallon {
            if record.pricePerGallon < currentLowest {
                vehicle.cachedLowestPricePerGallon = record.pricePerGallon
            }
        } else {
            vehicle.cachedLowestPricePerGallon = record.pricePerGallon
        }

        vehicle.cacheLastUpdated = Date()
    }

    /// Recalculate just the averages (MPG and price per gallon) from cached record values
    private static func recalculateAverages(for vehicle: Vehicle) {
        let records = vehicle.fuelingRecords ?? []
        guard !records.isEmpty else { return }

        // Average price per gallon
        let totalPrice = records.reduce(0.0) { $0 + $1.pricePerGallon }
        vehicle.cachedAveragePricePerGallon = totalPrice / Double(records.count)

        // Average MPG from full fill-ups
        let fullFillUps = records.filter { $0.isFullFillUp && $0.cachedMPG != nil }
        if !fullFillUps.isEmpty {
            let totalMPGMiles = fullFillUps.reduce(0.0) { $0 + ($1.cachedMilesDriven ?? 0) }
            let totalMPGGallons = fullFillUps.reduce(0.0) { $0 + $1.gallons }
            if totalMPGGallons > 0 {
                vehicle.cachedAverageMPG = totalMPGMiles / totalMPGGallons
            }
        }
    }

    /// Update statistics after deleting a record
    /// This triggers a full recalculation since deletion can affect subsequent records
    static func updateForDeletedRecord(vehicle: Vehicle) {
        recalculateAllStatistics(for: vehicle)
    }

    /// Update statistics after editing a record
    /// This triggers a full recalculation since edits can affect all calculations
    static func updateForEditedRecord(vehicle: Vehicle) {
        recalculateAllStatistics(for: vehicle)
    }

    // MARK: - Cache Validation

    /// Ensure cache is valid, recalculating if necessary
    static func ensureCacheValid(for vehicle: Vehicle) {
        if vehicle.needsCacheRebuild {
            recalculateAllStatistics(for: vehicle)
        }
    }

    /// Rebuild cache for all vehicles in the model context
    static func rebuildCacheForAllVehicles(in modelContext: ModelContext) {
        do {
            let descriptor = FetchDescriptor<Vehicle>()
            let vehicles = try modelContext.fetch(descriptor)

            for vehicle in vehicles {
                if vehicle.needsCacheRebuild {
                    recalculateAllStatistics(for: vehicle)
                }
            }

            try modelContext.save()
        } catch {
            print("Failed to rebuild cache for all vehicles: \(error)")
        }
    }
}

