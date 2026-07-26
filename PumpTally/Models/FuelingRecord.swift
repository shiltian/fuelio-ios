import SwiftUI
import SwiftData

/// Represents the type of fill-up for a fueling record
enum FillUpType: String, Codable, CaseIterable {
    case full = "full"        // Normal full tank fill-up
    case partial = "partial"  // Didn't fill the tank completely (affects NEXT record's MPG)
    case reset = "reset"      // Missed recording previous fill-up(s) (invalidates THIS record's MPG)

    var displayName: String {
        switch self {
        case .full: return String(localized: "Full Tank")
        case .partial: return String(localized: "Partial Fill")
        case .reset: return String(localized: "Missed Fueling")
        }
    }

    var description: String {
        switch self {
        case .full: return String(localized: "Filled the tank completely")
        case .partial: return String(localized: "Didn't fill completely (affects next efficiency calculation)")
        case .reset: return String(localized: "Missed recording previous fill-up(s)")
        }
    }

    var icon: String {
        switch self {
        case .full: return "fuelpump.fill"
        case .partial: return "exclamationmark.triangle.fill"
        case .reset: return "arrow.counterclockwise.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .full: return .green
        case .partial: return .yellow
        case .reset: return .red
        }
    }
}

@Model
final class FuelingRecord {
    // Keep FuelingRecordPersistenceService.RollbackSnapshot in sync when adding
    // a stored field that record editing can mutate.
    var id: UUID = UUID()
    var date: Date = Date()
    var odometer: Double = 0
    var pricePerFuelUnit: Double = 0
    var fuelAmount: Double = 0
    var totalCost: Double = 0
    var fillUpTypeRaw: String = FillUpType.full.rawValue  // Stored as String for SwiftData compatibility
    var notes: String?
    var createdAt: Date = Date()
    var modifiedAt: Date?

    var vehicle: Vehicle

    // MARK: - Cached Computed Values (for performance)
    // These are pre-computed and stored to avoid O(n²) lookups
    // Keep FuelingRecordPersistenceService.RollbackSnapshot in sync when adding a cache field.
    var cachedPreviousOdometer: Double?
    var cachedDistanceDriven: Double?
    var cachedEfficiency: Double?
    var cachedCostPerDistance: Double?

    // MARK: - Fill-up Type Accessor
    var fillUpType: FillUpType {
        get { FillUpType(rawValue: fillUpTypeRaw) ?? .full }
        set { fillUpTypeRaw = newValue.rawValue }
    }

    // Convenience computed properties for checking fill-up type
    var isPartialFillUp: Bool { fillUpType == .partial }
    var isReset: Bool { fillUpType == .reset }
    var isFullFillUp: Bool { fillUpType == .full }

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        odometer: Double,
        pricePerFuelUnit: Double,
        fuelAmount: Double,
        totalCost: Double,
        fillUpType: FillUpType = .full,
        notes: String? = nil,
        createdAt: Date = Date(),
        vehicle: Vehicle
    ) {
        self.id = id
        self.date = date
        self.odometer = odometer
        self.pricePerFuelUnit = pricePerFuelUnit
        self.fuelAmount = fuelAmount
        self.totalCost = totalCost
        self.fillUpTypeRaw = fillUpType.rawValue
        self.notes = notes
        self.createdAt = createdAt
        self.vehicle = vehicle
    }

    // MARK: - Cached Value Accessors
    // Use cached values if available, otherwise compute on-demand

    /// Get previous odometer reading (cached or fallback)
    func getPreviousOdometer(fallback: Double = 0) -> Double {
        cachedPreviousOdometer ?? fallback
    }

    /// Get distance driven (cached or computed)
    func getDistanceDriven() -> Double {
        if let cached = cachedDistanceDriven {
            return cached
        }
        guard let prevOdometer = cachedPreviousOdometer, prevOdometer > 0 else { return 0 }
        return odometer - prevOdometer
    }

    /// Get efficiency ratio (cached or computed)
    /// Returns distance/fuel ratio (higher = better, regardless of unit system)
    /// For display, use vehicle.unitSystem.efficiencyDisplayValue(from:) to convert
    func getEfficiency() -> Double {
        if let cached = cachedEfficiency {
            return cached
        }
        let distance = getDistanceDriven()
        guard fuelAmount > 0, distance > 0, !isPartialFillUp, !isReset else { return 0 }
        return distance / fuelAmount
    }

    /// Get cost per distance unit (cached or computed)
    func getCostPerDistance() -> Double {
        if let cached = cachedCostPerDistance {
            return cached
        }
        let distance = getDistanceDriven()
        guard distance > 0 else { return 0 }
        return totalCost / distance
    }

}

// MARK: - CSV Export/Import Support
extension FuelingRecord {
    static let csvHeader = "date,odometer,pricePerFuelUnit,fuelAmount,totalCost,fillUpType,notes"

    private static let isoFormatter = ISO8601DateFormatter()

    func toCSVRow() -> String {
        let dateString = Self.isoFormatter.string(from: date)
        let notesEscaped = (notes ?? "").replacingOccurrences(of: "\"", with: "\"\"")

        return "\(dateString),\(odometer),\(pricePerFuelUnit),\(fuelAmount),\(totalCost),\(fillUpType.rawValue),\"\(notesEscaped)\""
    }

    static func fromCSVRow(_ row: String, vehicle: Vehicle) -> FuelingRecord? {
        let components = CSVService.parseCSVLine(row)
        guard components.count >= 5 else { return nil }

        guard let date = isoFormatter.date(from: components[0]),
              let odometer = Double(components[1]),
              let pricePerFuelUnit = Double(components[2]),
              let fuelAmount = Double(components[3]),
              let totalCost = Double(components[4]) else {
            return nil
        }

        // Parse fillUpType - supports new format and legacy boolean format
        let fillUpType: FillUpType
        if components.count > 5 {
            let typeValue = components[5].lowercased()
            if let parsed = FillUpType(rawValue: typeValue) {
                // New format: full, partial, reset
                fillUpType = parsed
            } else if typeValue == "true" {
                // Legacy format: isPartialFillUp was true
                fillUpType = .partial
            } else {
                fillUpType = .full
            }
        } else {
            fillUpType = .full
        }

        let notes = components.count > 6 && !components[6].isEmpty ? components[6] : nil

        return FuelingRecord(
            date: date,
            odometer: odometer,
            pricePerFuelUnit: pricePerFuelUnit,
            fuelAmount: fuelAmount,
            totalCost: totalCost,
            fillUpType: fillUpType,
            notes: notes,
            vehicle: vehicle
        )
    }

}
