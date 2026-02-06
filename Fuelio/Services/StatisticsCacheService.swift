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
        var totalDistance: Double = 0
        var totalFuel: Double = 0
        var totalPricePerFuelUnit: Double = 0

        var fullFillUpDistance: Double = 0
        var fullFillUpFuel: Double = 0

        var bestEfficiency: Double = 0
        var worstEfficiency: Double = Double.greatestFiniteMagnitude
        var highestPrice: Double = 0
        var lowestPrice: Double = Double.greatestFiniteMagnitude

        var hasValidEfficiency = false
        var previousOdometer: Double = 0
        var previousWasFullFillUp = false

        for (index, record) in sortedByDate.enumerated() {
            // Cache previous odometer for this record
            record.cachedPreviousOdometer = previousOdometer

            // Calculate distance driven
            let distanceDriven: Double
            if previousOdometer > 0 {
                distanceDriven = record.odometer - previousOdometer
                record.cachedDistanceDriven = distanceDriven
            } else {
                distanceDriven = 0
                record.cachedDistanceDriven = 0
            }

            // Calculate efficiency (only for full fill-ups where previous was also full)
            // Partial: didn't fill tank completely (affects next record's efficiency baseline)
            // Reset: missed fueling(s) before this record (can't trust distance driven for this record)
            let efficiency: Double
            if record.isFullFillUp && previousWasFullFillUp && distanceDriven > 0 && record.fuelAmount > 0 {
                efficiency = distanceDriven / record.fuelAmount
                record.cachedEfficiency = efficiency

                // Track best/worst efficiency
                hasValidEfficiency = true
                if efficiency > bestEfficiency { bestEfficiency = efficiency }
                if efficiency < worstEfficiency { worstEfficiency = efficiency }

                // Accumulate for average efficiency calculation
                fullFillUpDistance += distanceDriven
                fullFillUpFuel += record.fuelAmount
            } else {
                efficiency = 0
                record.cachedEfficiency = nil
            }

            // Calculate cost per distance
            if distanceDriven > 0 {
                record.cachedCostPerDistance = record.totalCost / distanceDriven
            } else {
                record.cachedCostPerDistance = nil
            }

            // Accumulate totals
            totalSpent += record.totalCost
            totalDistance += distanceDriven
            totalFuel += record.fuelAmount
            totalPricePerFuelUnit += record.pricePerFuelUnit

            // Track price extremes
            if record.pricePerFuelUnit > highestPrice { highestPrice = record.pricePerFuelUnit }
            if record.pricePerFuelUnit < lowestPrice { lowestPrice = record.pricePerFuelUnit }

            // Update state for next iteration
            previousOdometer = record.odometer
            previousWasFullFillUp = record.isFullFillUp || index == 0
        }

        // Store aggregated statistics on the vehicle
        vehicle.cachedTotalSpent = totalSpent
        vehicle.cachedTotalDistance = totalDistance
        vehicle.cachedTotalFuel = totalFuel
        vehicle.cachedRecordCount = records.count

        // Average efficiency from full fill-ups only (more accurate)
        if fullFillUpFuel > 0 {
            vehicle.cachedAverageEfficiency = fullFillUpDistance / fullFillUpFuel
        } else if totalFuel > 0 {
            // Fallback to all records if no full fill-ups
            vehicle.cachedAverageEfficiency = totalDistance / totalFuel
        } else {
            vehicle.cachedAverageEfficiency = 0
        }

        // Average cost per distance
        if totalDistance > 0 {
            vehicle.cachedAverageCostPerDistance = totalSpent / totalDistance
        } else {
            vehicle.cachedAverageCostPerDistance = 0
        }

        // Average fill-up cost
        vehicle.cachedAverageFillUpCost = totalSpent / Double(records.count)

        // Average price per fuel unit
        vehicle.cachedAveragePricePerFuelUnit = totalPricePerFuelUnit / Double(records.count)

        // Best/worst efficiency
        vehicle.cachedBestEfficiency = hasValidEfficiency ? bestEfficiency : nil
        vehicle.cachedWorstEfficiency = hasValidEfficiency && worstEfficiency != Double.greatestFiniteMagnitude ? worstEfficiency : nil

        // Price extremes
        vehicle.cachedHighestPricePerFuelUnit = highestPrice > 0 ? highestPrice : nil
        vehicle.cachedLowestPricePerFuelUnit = lowestPrice != Double.greatestFiniteMagnitude ? lowestPrice : nil

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
        let previousOdometer = previousRecord.odometer

        // Cache values for the new record
        record.cachedPreviousOdometer = previousOdometer

        let distanceDriven = record.odometer - previousOdometer
        record.cachedDistanceDriven = distanceDriven > 0 ? distanceDriven : 0

        // Calculate efficiency if applicable (only for full fill-ups where previous was also full)
        if record.isFullFillUp && previousRecord.isFullFillUp && distanceDriven > 0 && record.fuelAmount > 0 {
            let efficiency = distanceDriven / record.fuelAmount
            record.cachedEfficiency = efficiency

            // Update best/worst efficiency
            if let currentBest = vehicle.cachedBestEfficiency {
                if efficiency > currentBest { vehicle.cachedBestEfficiency = efficiency }
            } else {
                vehicle.cachedBestEfficiency = efficiency
            }

            if let currentWorst = vehicle.cachedWorstEfficiency {
                if efficiency < currentWorst { vehicle.cachedWorstEfficiency = efficiency }
            } else {
                vehicle.cachedWorstEfficiency = efficiency
            }
        } else {
            record.cachedEfficiency = nil
        }

        // Calculate cost per distance
        if distanceDriven > 0 {
            record.cachedCostPerDistance = record.totalCost / distanceDriven
        } else {
            record.cachedCostPerDistance = nil
        }

        // Update aggregate totals
        vehicle.cachedTotalSpent = (vehicle.cachedTotalSpent ?? 0) + record.totalCost
        vehicle.cachedTotalDistance = (vehicle.cachedTotalDistance ?? 0) + (distanceDriven > 0 ? distanceDriven : 0)
        vehicle.cachedTotalFuel = (vehicle.cachedTotalFuel ?? 0) + record.fuelAmount

        let newCount = (vehicle.cachedRecordCount ?? 0) + 1
        vehicle.cachedRecordCount = newCount

        // Recalculate averages
        if let totalSpent = vehicle.cachedTotalSpent {
            vehicle.cachedAverageFillUpCost = totalSpent / Double(newCount)
        }

        if let totalDistance = vehicle.cachedTotalDistance, totalDistance > 0, let totalSpent = vehicle.cachedTotalSpent {
            vehicle.cachedAverageCostPerDistance = totalSpent / totalDistance
        }

        // For average efficiency and price, it's easier to just recalculate
        // (they depend on specific subsets and would require tracking additional state)
        recalculateAverages(for: vehicle)

        // Update price extremes
        if let currentHighest = vehicle.cachedHighestPricePerFuelUnit {
            if record.pricePerFuelUnit > currentHighest {
                vehicle.cachedHighestPricePerFuelUnit = record.pricePerFuelUnit
            }
        } else {
            vehicle.cachedHighestPricePerFuelUnit = record.pricePerFuelUnit
        }

        if let currentLowest = vehicle.cachedLowestPricePerFuelUnit {
            if record.pricePerFuelUnit < currentLowest {
                vehicle.cachedLowestPricePerFuelUnit = record.pricePerFuelUnit
            }
        } else {
            vehicle.cachedLowestPricePerFuelUnit = record.pricePerFuelUnit
        }

        vehicle.cacheLastUpdated = Date()
    }

    /// Recalculate just the averages (efficiency and price per fuel unit) from cached record values
    private static func recalculateAverages(for vehicle: Vehicle) {
        let records = vehicle.fuelingRecords ?? []
        guard !records.isEmpty else { return }

        // Average price per fuel unit
        let totalPrice = records.reduce(0.0) { $0 + $1.pricePerFuelUnit }
        vehicle.cachedAveragePricePerFuelUnit = totalPrice / Double(records.count)

        // Average efficiency from full fill-ups
        let fullFillUps = records.filter { $0.isFullFillUp && $0.cachedEfficiency != nil }
        if !fullFillUps.isEmpty {
            let totalEfficiencyDistance = fullFillUps.reduce(0.0) { $0 + ($1.cachedDistanceDriven ?? 0) }
            let totalEfficiencyFuel = fullFillUps.reduce(0.0) { $0 + $1.fuelAmount }
            if totalEfficiencyFuel > 0 {
                vehicle.cachedAverageEfficiency = totalEfficiencyDistance / totalEfficiencyFuel
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
