import Foundation
import SwiftData

struct CSVImportRecordSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let lineNumber: Int
    let date: Date
    let odometer: Double
    let pricePerFuelUnit: Double
    let fuelAmount: Double
    let totalCost: Double
    let fillUpType: FillUpType
    let notes: String?
}

enum CSVImportError: LocalizedError, Equatable, Sendable {
    case invalidFile(String)
    case invalidRow(line: Int, reason: String)
    case invalidChronology(line: Int, reason: String)
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .invalidFile(let reason):
            return reason
        case .invalidRow(let line, let reason):
            return "Row \(line): \(reason)"
        case .invalidChronology(let line, let reason):
            return "Row \(line) has invalid odometer chronology: \(reason)"
        case .persistenceFailed:
            return String(localized: "Unable to save the imported records. No data was changed. Please try again.")
        }
    }
}

/// Strict, all-or-nothing CSV import pipeline.
///
/// Parsing and validation use value types only. SwiftData models are created
/// only after every row has passed structural and chronology validation.
enum CSVImportService {
    static func parse(_ content: String) throws -> [CSVImportRecordSnapshot] {
        let logicalRecords = try splitLogicalRecords(content)
        guard let header = logicalRecords.first else {
            throw CSVImportError.invalidFile(String(localized: "The file is empty"))
        }
        guard logicalRecords.count > 1 else {
            throw CSVImportError.invalidFile(
                String(localized: "The file only contains a header row with no data")
            )
        }
        try validateHeader(header.content)

        var records: [CSVImportRecordSnapshot] = []
        let dateParser = ImportDateParser()

        for logicalRecord in logicalRecords.dropFirst() {
            let lineNumber = logicalRecord.lineNumber
            let fields = CSVService.parseCSVLine(logicalRecord.content)
            guard (5...7).contains(fields.count) else {
                throw CSVImportError.invalidRow(
                    line: lineNumber,
                    reason: String(localized: "expected between 5 and 7 columns")
                )
            }

            guard let date = dateParser.parse(fields[0]) else {
                throw CSVImportError.invalidRow(
                    line: lineNumber,
                    reason: String(localized: "the date is invalid")
                )
            }

            let odometer = try positiveNumber(
                fields[1],
                name: String(localized: "odometer"),
                line: lineNumber
            )
            let price = try nonnegativeNumber(
                fields[2],
                name: String(localized: "price per fuel unit"),
                line: lineNumber
            )
            let fuel = try positiveNumber(
                fields[3],
                name: String(localized: "fuel amount"),
                line: lineNumber
            )
            let cost = try nonnegativeNumber(
                fields[4],
                name: String(localized: "total cost"),
                line: lineNumber
            )
            let fillUpType = try parseFillUpType(
                fields.count > 5 ? fields[5] : "",
                line: lineNumber
            )
            let notes = fields.count > 6 && !fields[6].isEmpty ? fields[6] : nil

            records.append(
                CSVImportRecordSnapshot(
                    id: UUID(),
                    lineNumber: lineNumber,
                    date: date,
                    odometer: odometer,
                    pricePerFuelUnit: price,
                    fuelAmount: fuel,
                    totalCost: cost,
                    fillUpType: fillUpType,
                    notes: notes
                )
            )
        }

        guard !records.isEmpty else {
            throw CSVImportError.invalidFile(
                String(localized: "The file contains no importable records")
            )
        }
        return records
    }

    static func validateChronology(
        _ records: [CSVImportRecordSnapshot],
        existingRecords: [OdometerReadingSnapshot]
    ) throws {
        let importedReadings = records.map {
            OdometerReadingSnapshot(id: $0.id, date: $0.date, odometer: $0.odometer)
        }
        let allReadings = existingRecords + importedReadings

        for record in records {
            let validation = OdometerChronologyValidator.validate(
                date: record.date,
                odometer: record.odometer,
                records: allReadings
            )
            guard let issue = validation.issue else { continue }

            let reason: String
            switch issue {
            case .invalidReading:
                reason = String(localized: "the reading must be a positive finite number")
            case .notGreaterThanPredecessor(let predecessor):
                reason = String(
                    localized: "the reading must be greater than \(formatted(predecessor.odometer))"
                )
            case .notLessThanSuccessor(let successor):
                reason = String(
                    localized: "the reading must be less than \(formatted(successor.odometer))"
                )
            }
            throw CSVImportError.invalidChronology(
                line: record.lineNumber,
                reason: reason
            )
        }
    }

    @MainActor
    static func importRecords(
        _ records: [CSVImportRecordSnapshot],
        into vehicle: Vehicle,
        context: ModelContext,
        commit: FuelingRecordPersistenceService.Commit = { try $0.save() }
    ) throws -> [FuelingRecord] {
        try validateChronology(
            records,
            existingRecords: (vehicle.fuelingRecords ?? []).map(
                OdometerReadingSnapshot.init(record:)
            )
        )

        let modifiedAt = Date()
        return try FuelingRecordPersistenceService.insertBatch(
            into: vehicle,
            context: context,
            commit: commit
        ) {
            records.map { snapshot in
                let record = FuelingRecord(
                    id: snapshot.id,
                    date: snapshot.date,
                    odometer: snapshot.odometer,
                    pricePerFuelUnit: snapshot.pricePerFuelUnit,
                    fuelAmount: snapshot.fuelAmount,
                    totalCost: snapshot.totalCost,
                    fillUpType: snapshot.fillUpType,
                    notes: snapshot.notes,
                    vehicle: vehicle
                )
                record.modifiedAt = modifiedAt
                return record
            }
        }
    }

    private static func positiveNumber(
        _ text: String,
        name: String,
        line: Int
    ) throws -> Double {
        guard let value = Double(text), value.isFinite, value > 0 else {
            throw CSVImportError.invalidRow(
                line: line,
                reason: "\(name) must be a positive finite number"
            )
        }
        return value
    }

    private static func nonnegativeNumber(
        _ text: String,
        name: String,
        line: Int
    ) throws -> Double {
        guard let value = Double(text), value.isFinite, value >= 0 else {
            throw CSVImportError.invalidRow(
                line: line,
                reason: "\(name) must be a nonnegative finite number"
            )
        }
        return value
    }

    private static func validateHeader(_ line: String) throws {
        let fields = CSVService.parseCSVLine(line).map {
            $0.lowercased().filter(\.isLetter)
        }
        let acceptedColumns: [Set<String>] = [
            ["date", "timestamp", "time"],
            ["odometer"],
            ["price", "priceperfuelunit"],
            ["fuel", "fuelamount"],
            ["cost", "totalcost"]
        ]
        guard fields.count >= acceptedColumns.count else {
            throw CSVImportError.invalidFile(
                String(localized: "The CSV header must contain date, odometer, price, fuel amount, and total cost columns.")
            )
        }
        for index in acceptedColumns.indices {
            guard acceptedColumns[index].contains(fields[index]) else {
                throw CSVImportError.invalidFile(
                    String(localized: "The CSV columns are missing or in an unsupported order.")
                )
            }
        }
    }

    private struct LogicalRecord {
        let lineNumber: Int
        let content: String
    }

    private static func splitLogicalRecords(
        _ content: String
    ) throws -> [LogicalRecord] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let physicalLines = normalized.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )

        var records: [LogicalRecord] = []
        var currentContent: String?
        var currentStartLine = 0
        var insideQuotes = false

        for (index, lineSlice) in physicalLines.enumerated() {
            let line = String(lineSlice)
            let lineNumber = index + 1

            if currentContent == nil {
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                    continue
                }
                currentContent = line
                currentStartLine = lineNumber
            } else {
                currentContent?.append("\n")
                currentContent?.append(line)
            }

            updateQuoteState(for: line, insideQuotes: &insideQuotes)
            if !insideQuotes, let completeRecord = currentContent {
                records.append(
                    LogicalRecord(
                        lineNumber: currentStartLine,
                        content: completeRecord
                    )
                )
                currentContent = nil
            }
        }

        if insideQuotes {
            throw CSVImportError.invalidRow(
                line: currentStartLine,
                reason: String(localized: "quoted text is not closed")
            )
        }
        return records
    }

    private static func updateQuoteState(
        for line: String,
        insideQuotes: inout Bool
    ) {
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            if characters[index] == "\"" {
                if insideQuotes,
                   index + 1 < characters.count,
                   characters[index + 1] == "\"" {
                    index += 2
                    continue
                }
                insideQuotes.toggle()
            }
            index += 1
        }
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(
            .number.precision(.fractionLength(0...3))
        )
    }

    private static func parseFillUpType(
        _ text: String,
        line: Int
    ) throws -> FillUpType {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty || normalized == "false" {
            return .full
        }
        if normalized == "true" {
            return .partial
        }
        guard let fillUpType = FillUpType(rawValue: normalized) else {
            throw CSVImportError.invalidRow(
                line: line,
                reason: String(localized: "fill-up type must be full, partial, or reset")
            )
        }
        return fillUpType
    }

    private struct ImportDateParser {
        private let isoFormatter = ISO8601DateFormatter()
        private let dateFormatters: [DateFormatter]

        init() {
            dateFormatters = ["yyyy-MM-dd", "MM/dd/yyyy"].map { format in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = format
                formatter.isLenient = false
                return formatter
            }
        }

        func parse(_ text: String) -> Date? {
            if let date = isoFormatter.date(from: text) {
                return date
            }
            for formatter in dateFormatters {
                if let date = formatter.date(from: text) {
                    return date
                }
            }
            return nil
        }
    }
}
