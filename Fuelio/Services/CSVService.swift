import Foundation

/// Service for handling CSV import and export of fueling records
enum CSVService {

    // MARK: - Export

    /// Export fueling records to CSV format
    /// - Parameter records: Array of FuelingRecord to export
    /// - Returns: CSV formatted string
    static func exportRecords(_ records: [FuelingRecord]) -> String {
        let rows = records.sorted(by: { $0.date < $1.date }).map { $0.toCSVRow() }
        return ([FuelingRecord.csvHeader] + rows).joined(separator: "\n") + "\n"
    }

    /// Export multiple vehicles and their records to CSV format
    /// - Parameter vehicles: Array of Vehicle to export
    /// - Returns: CSV formatted string containing all vehicles' records
    static func exportAllVehicles(_ vehicles: [Vehicle]) -> String {
        let header = "vehicleName,vehicleMake,vehicleModel,vehicleYear,unitSystem," + FuelingRecord.csvHeader

        let rows = vehicles.flatMap { vehicle in
            vehicle.sortedRecords.map { record in
                let vehicleInfo = "\"\(vehicle.name)\",\"\(vehicle.make ?? "")\",\"\(vehicle.model ?? "")\",\(vehicle.year ?? 0),\(vehicle.unitSystemRaw)"
                return vehicleInfo + "," + record.toCSVRow()
            }
        }

        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    // MARK: - Import

    /// Import fueling records from CSV content for a specific vehicle
    /// - Parameters:
    ///   - content: CSV formatted string
    ///   - vehicle: Vehicle to attach to every record
    /// - Returns: Array of FuelingRecord parsed from CSV
    static func importRecords(from content: String, vehicle: Vehicle) -> [FuelingRecord] {
        var records: [FuelingRecord] = []

        let lines = content.components(separatedBy: .newlines)

        // Skip header row
        let dataLines = lines.dropFirst().filter { !$0.isEmpty }

        for line in dataLines {
            if let record = FuelingRecord.fromCSVRow(line, vehicle: vehicle) {
                records.append(record)
            }
        }

        return records
    }

    /// Parse a simple CSV file format (for manual data entry or basic imports)
    /// Expected format: date,odometer,pricePerFuelUnit,fuelAmount,totalCost,fillUpType,notes
    /// - Parameters:
    ///   - content: CSV formatted string
    ///   - vehicle: Vehicle to attach to every record
    /// - Returns: Array of FuelingRecord
    private static let simpleDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let usDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy"
        return f
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    static func importSimpleFormat(from content: String, vehicle: Vehicle) -> [FuelingRecord] {
        var records: [FuelingRecord] = []

        let lines = content.components(separatedBy: .newlines)
        let dataLines = lines.dropFirst().filter { !$0.isEmpty }

        for line in dataLines {
            let components = parseCSVLine(line)
            guard components.count >= 5 else { continue }

            // Try to parse date in various formats
            var date: Date?
            if let d = simpleDateFormatter.date(from: components[0]) {
                date = d
            } else if let d = isoFormatter.date(from: components[0]) {
                date = d
            } else {
                if let d = usDateFormatter.date(from: components[0]) {
                    date = d
                }
            }

            guard let parsedDate = date,
                  let odometer = Double(components[1]),
                  let pricePerFuelUnit = Double(components[2]),
                  let fuelAmount = Double(components[3]),
                  let totalCost = Double(components[4]) else {
                continue
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

            let record = FuelingRecord(
                date: parsedDate,
                odometer: odometer,
                pricePerFuelUnit: pricePerFuelUnit,
                fuelAmount: fuelAmount,
                totalCost: totalCost,
                fillUpType: fillUpType,
                notes: notes,
                vehicle: vehicle
            )

            records.append(record)
        }

        return records
    }

    // MARK: - Helpers

    /// Parse a CSV line handling quoted fields
    /// - Parameter line: Single CSV line
    /// - Returns: Array of field values
    static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var insideQuotes = false

        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))

        return result
    }

    /// Validate CSV content before import
    /// - Parameter content: CSV formatted string
    /// - Returns: Tuple with validity and error message if invalid
    static func validateCSV(_ content: String) -> (isValid: Bool, error: String?) {
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return (false, String(localized: "The file is empty"))
        }

        guard lines.count > 1 else {
            return (false, String(localized: "The file only contains a header row with no data"))
        }

        // Check if first line looks like a header
        let firstLine = lines[0].lowercased()
        let hasHeader = firstLine.contains("date") || firstLine.contains("odometer") || firstLine.contains("fuel")

        if !hasHeader {
            return (false, String(localized: "The file doesn't appear to have a valid header row"))
        }

        return (true, nil)
    }

    /// Generate a sample CSV template
    /// - Returns: CSV formatted string with headers and example row
    static func generateTemplate() -> String {
"""
date,odometer,pricePerFuelUnit,fuelAmount,totalCost,fillUpType,notes
2024-01-15,12500,3.459,10.5,36.32,full,"First fill-up of the year"
2024-01-22,12800,3.399,11.2,38.07,full,""
"""
    }
}
