import Foundation
import SwiftData

@Model
final class FuelingRecord {
    var id: UUID
    var date: Date
    var currentMiles: Double
    var previousMiles: Double
    var pricePerGallon: Double
    var gallons: Double
    var totalCost: Double
    var isPartialFillUp: Bool
    var isInitialRecord: Bool  // First record sets baseline odometer, MPG not calculated
    var notes: String?
    var createdAt: Date

    var vehicle: Vehicle?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        currentMiles: Double,
        previousMiles: Double,
        pricePerGallon: Double,
        gallons: Double,
        totalCost: Double,
        isPartialFillUp: Bool = false,
        isInitialRecord: Bool = false,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.currentMiles = currentMiles
        self.previousMiles = previousMiles
        self.pricePerGallon = pricePerGallon
        self.gallons = gallons
        self.totalCost = totalCost
        self.isPartialFillUp = isPartialFillUp
        self.isInitialRecord = isInitialRecord
        self.notes = notes
        self.createdAt = createdAt
    }

    // MARK: - Computed Properties

    /// Miles driven since last fill-up
    var milesDriven: Double {
        currentMiles - previousMiles
    }

    /// Miles per gallon for this fill-up
    /// Returns 0 for initial records since they only set the baseline odometer
    var mpg: Double {
        guard !isInitialRecord else { return 0 }
        guard gallons > 0 else { return 0 }
        return milesDriven / gallons
    }

    /// Cost per mile for this fill-up
    var costPerMile: Double {
        guard milesDriven > 0 else { return 0 }
        return totalCost / milesDriven
    }

    // MARK: - Static Calculation Helpers

    /// Calculate total cost from price per gallon and gallons
    static func calculateTotalCost(pricePerGallon: Double, gallons: Double) -> Double {
        return pricePerGallon * gallons
    }

    /// Calculate gallons from total cost and price per gallon
    static func calculateGallons(totalCost: Double, pricePerGallon: Double) -> Double {
        guard pricePerGallon > 0 else { return 0 }
        return totalCost / pricePerGallon
    }

    /// Calculate price per gallon from total cost and gallons
    static func calculatePricePerGallon(totalCost: Double, gallons: Double) -> Double {
        guard gallons > 0 else { return 0 }
        return totalCost / gallons
    }
}

// MARK: - CSV Export/Import Support
extension FuelingRecord {
    static let csvHeader = "id,date,currentMiles,previousMiles,pricePerGallon,gallons,totalCost,isPartialFillUp,notes,vehicleId"

    func toCSVRow(vehicleId: UUID?) -> String {
        let dateFormatter = ISO8601DateFormatter()
        let dateString = dateFormatter.string(from: date)
        let notesEscaped = (notes ?? "").replacingOccurrences(of: "\"", with: "\"\"")
        let vehicleIdString = vehicleId?.uuidString ?? ""

        return "\(id.uuidString),\(dateString),\(currentMiles),\(previousMiles),\(pricePerGallon),\(gallons),\(totalCost),\(isPartialFillUp),\"\(notesEscaped)\",\(vehicleIdString)"
    }

    static func fromCSVRow(_ row: String) -> (record: FuelingRecord, vehicleId: UUID?)? {
        let components = parseCSVRow(row)
        guard components.count >= 9 else { return nil }

        let dateFormatter = ISO8601DateFormatter()

        guard let id = UUID(uuidString: components[0]),
              let date = dateFormatter.date(from: components[1]),
              let currentMiles = Double(components[2]),
              let previousMiles = Double(components[3]),
              let pricePerGallon = Double(components[4]),
              let gallons = Double(components[5]),
              let totalCost = Double(components[6]) else {
            return nil
        }

        let isPartialFillUp = components[7].lowercased() == "true"
        let notes = components[8].isEmpty ? nil : components[8]
        let vehicleId = components.count > 9 ? UUID(uuidString: components[9]) : nil

        let record = FuelingRecord(
            id: id,
            date: date,
            currentMiles: currentMiles,
            previousMiles: previousMiles,
            pricePerGallon: pricePerGallon,
            gallons: gallons,
            totalCost: totalCost,
            isPartialFillUp: isPartialFillUp,
            notes: notes
        )

        return (record, vehicleId)
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

