import SwiftUI
import SwiftData

/// Represents the type of fill-up for a fueling record
enum FillUpType: String, Codable, CaseIterable {
    case full = "full"        // Normal full tank fill-up
    case partial = "partial"  // Didn't fill the tank completely (affects NEXT record's MPG)
    case reset = "reset"      // Missed recording previous fill-up(s) (invalidates THIS record's MPG)

    var displayName: String {
        switch self {
        case .full: return "Full Tank"
        case .partial: return "Partial Fill"
        case .reset: return "Missed Fueling"
        }
    }

    var description: String {
        switch self {
        case .full: return "Filled the tank completely"
        case .partial: return "Didn't fill completely (affects next MPG)"
        case .reset: return "Missed recording previous fill-up(s)"
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
    var id: UUID = UUID()
    var date: Date = Date()
    var currentMiles: Double = 0
    var pricePerGallon: Double = 0
    var gallons: Double = 0
    var totalCost: Double = 0
    var fillUpTypeRaw: String = FillUpType.full.rawValue  // Stored as String for SwiftData compatibility
    var notes: String?
    var createdAt: Date = Date()

    var vehicle: Vehicle

    // MARK: - Cached Computed Values (for performance)
    // These are pre-computed and stored to avoid O(n²) lookups
    var cachedPreviousMiles: Double?
    var cachedMilesDriven: Double?
    var cachedMPG: Double?
    var cachedCostPerMile: Double?

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
        currentMiles: Double,
        pricePerGallon: Double,
        gallons: Double,
        totalCost: Double,
        fillUpType: FillUpType = .full,
        notes: String? = nil,
        createdAt: Date = Date(),
        vehicle: Vehicle
    ) {
        self.id = id
        self.date = date
        self.currentMiles = currentMiles
        self.pricePerGallon = pricePerGallon
        self.gallons = gallons
        self.totalCost = totalCost
        self.fillUpTypeRaw = fillUpType.rawValue
        self.notes = notes
        self.createdAt = createdAt
        self.vehicle = vehicle
    }

    /// Deprecated: prefer init that requires a vehicle. Kept to avoid widespread call-site changes.
    @available(*, deprecated, message: "Pass vehicle explicitly")
    convenience init(
        id: UUID = UUID(),
        date: Date = Date(),
        currentMiles: Double,
        pricePerGallon: Double,
        gallons: Double,
        totalCost: Double,
        fillUpType: FillUpType = .full,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        let placeholderVehicle = Vehicle(name: "Unassigned")
        self.init(
            id: id,
            date: date,
            currentMiles: currentMiles,
            pricePerGallon: pricePerGallon,
            gallons: gallons,
            totalCost: totalCost,
            fillUpType: fillUpType,
            notes: notes,
            createdAt: createdAt,
            vehicle: placeholderVehicle
        )
    }

    // MARK: - Cached Value Accessors
    // Use cached values if available, otherwise compute on-demand

    /// Get previous miles (cached or computed)
    func getPreviousMiles(fallback: Double = 0) -> Double {
        cachedPreviousMiles ?? fallback
    }

    /// Get miles driven (cached or computed)
    func getMilesDriven() -> Double {
        if let cached = cachedMilesDriven {
            return cached
        }
        guard let prevMiles = cachedPreviousMiles, prevMiles > 0 else { return 0 }
        return currentMiles - prevMiles
    }

    /// Get MPG (cached or computed)
    func getMPG() -> Double {
        if let cached = cachedMPG {
            return cached
        }
        let miles = getMilesDriven()
        guard gallons > 0, miles > 0, !isPartialFillUp, !isReset else { return 0 }
        return miles / gallons
    }

    /// Get cost per mile (cached or computed)
    func getCostPerMile() -> Double {
        if let cached = cachedCostPerMile {
            return cached
        }
        let miles = getMilesDriven()
        guard miles > 0 else { return 0 }
        return totalCost / miles
    }

}

// MARK: - CSV Export/Import Support
extension FuelingRecord {
    static let csvHeader = "date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes"

    func toCSVRow() -> String {
        let dateFormatter = ISO8601DateFormatter()
        let dateString = dateFormatter.string(from: date)
        let notesEscaped = (notes ?? "").replacingOccurrences(of: "\"", with: "\"\"")

        return "\(dateString),\(currentMiles),\(pricePerGallon),\(gallons),\(totalCost),\(fillUpType.rawValue),\"\(notesEscaped)\""
    }

    static func fromCSVRow(_ row: String, vehicle: Vehicle) -> FuelingRecord? {
        let components = parseCSVRow(row)
        guard components.count >= 5 else { return nil }

        let dateFormatter = ISO8601DateFormatter()

        guard let date = dateFormatter.date(from: components[0]),
              let currentMiles = Double(components[1]),
              let pricePerGallon = Double(components[2]),
              let gallons = Double(components[3]),
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
            currentMiles: currentMiles,
            pricePerGallon: pricePerGallon,
            gallons: gallons,
            totalCost: totalCost,
            fillUpType: fillUpType,
            notes: notes,
            vehicle: vehicle
        )
    }

    private static func parseCSVRow(_ row: String) -> [String] {
        var result: [String] = []
        var current = ""
        var insideQuotes = false

        for char in row {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)

        return result
    }
}

