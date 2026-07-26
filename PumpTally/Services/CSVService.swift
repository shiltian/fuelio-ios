import Foundation

/// CSV export plus the low-level field parser shared by strict imports.
enum CSVService {
    static let csvHeader =
        "date,odometer,pricePerFuelUnit,fuelAmount,totalCost,fillUpType,notes"

    struct RecordSnapshot: Sendable {
        let id: UUID
        let date: Date
        let odometer: Double
        let pricePerFuelUnit: Double
        let fuelAmount: Double
        let totalCost: Double
        let fillUpTypeRaw: String
        let notes: String?

        init(record: FuelingRecord) {
            self.id = record.id
            self.date = record.date
            self.odometer = record.odometer
            self.pricePerFuelUnit = record.pricePerFuelUnit
            self.fuelAmount = record.fuelAmount
            self.totalCost = record.totalCost
            self.fillUpTypeRaw = record.fillUpType.rawValue
            self.notes = record.notes
        }
    }

    /// Export value snapshots to CSV format. This is safe to run away from the
    /// main actor because it does not touch SwiftData model objects.
    static func exportRecords(_ records: [RecordSnapshot]) -> String {
        let formatter = ISO8601DateFormatter()
        let rows = records.sorted {
            OdometerChronologyValidator.areInIncreasingOrder(
                lhsDate: $0.date,
                lhsOdometer: $0.odometer,
                lhsID: $0.id,
                rhsDate: $1.date,
                rhsOdometer: $1.odometer,
                rhsID: $1.id
            )
        }.map { snapshot in
            let dateString = formatter.string(from: snapshot.date)
            let notesEscaped = (snapshot.notes ?? "").replacingOccurrences(of: "\"", with: "\"\"")

            return "\(dateString),\(snapshot.odometer),\(snapshot.pricePerFuelUnit),\(snapshot.fuelAmount),\(snapshot.totalCost),\(snapshot.fillUpTypeRaw),\"\(notesEscaped)\""
        }
        return ([csvHeader] + rows).joined(separator: "\n") + "\n"
    }

    /// Parse a CSV line handling quoted fields
    /// - Parameter line: Single CSV line
    /// - Returns: Array of field values
    static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var insideQuotes = false
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            let char = characters[index]
            if char == "\"" {
                if insideQuotes,
                   index + 1 < characters.count,
                   characters[index + 1] == "\"" {
                    current.append("\"")
                    index += 2
                    continue
                }
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
            index += 1
        }
        result.append(current.trimmingCharacters(in: .whitespaces))

        return result
    }
}
