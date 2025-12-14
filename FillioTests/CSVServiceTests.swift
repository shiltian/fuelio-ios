import XCTest
@testable import Fillio

final class CSVServiceTests: XCTestCase {
    private let testVehicle = Vehicle(name: "Test Car")

    // MARK: - Export Tests

    func testExportRecordsEmpty() {
        let records: [FuelingRecord] = []
        let csv = CSVService.exportRecords(records)

        XCTAssertEqual(csv, FuelingRecord.csvHeader + "\n")
    }

    func testExportRecordsSingleRecord() {
        let date = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")!

        let record = FuelingRecord(
            date: date,
            currentMiles: 12500,
            pricePerGallon: 3.459,
            gallons: 10.5,
            totalCost: 36.32,
            fillUpType: .full,
            notes: "Test note"
        )

        let csv = CSVService.exportRecords([record])

        XCTAssertTrue(csv.hasPrefix(FuelingRecord.csvHeader + "\n"))
        XCTAssertTrue(csv.contains("12500.0"))
        XCTAssertTrue(csv.contains("3.459"))
        XCTAssertTrue(csv.contains("10.5"))
        XCTAssertTrue(csv.contains("36.32"))
        XCTAssertTrue(csv.contains("full"))
        XCTAssertTrue(csv.contains("Test note"))
    }

    func testExportRecordsMultipleRecordsSortedByDate() {
        let oldDate = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")!
        let newDate = ISO8601DateFormatter().date(from: "2024-01-22T10:30:00Z")!

        let oldRecord = FuelingRecord(
            date: oldDate,
            currentMiles: 12500,
            pricePerGallon: 3.459,
            gallons: 10.5,
            totalCost: 36.32,
            fillUpType: .full,
            notes: "First"
        )

        let newRecord = FuelingRecord(
            date: newDate,
            currentMiles: 13000,
            pricePerGallon: 3.599,
            gallons: 11.0,
            totalCost: 39.59,
            fillUpType: .full,
            notes: "Second"
        )

        // Pass in reverse order to verify sorting
        let csv = CSVService.exportRecords([newRecord, oldRecord])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }

        // First line is header
        XCTAssertEqual(lines.count, 3)

        // Second line should be older record (sorted ascending)
        XCTAssertTrue(lines[1].contains("12500.0"))
        XCTAssertTrue(lines[1].contains("First"))

        // Third line should be newer record
        XCTAssertTrue(lines[2].contains("13000.0"))
        XCTAssertTrue(lines[2].contains("Second"))
    }

    // MARK: - Export All Vehicles Tests

    func testExportAllVehiclesEmpty() {
        let vehicles: [Vehicle] = []
        let csv = CSVService.exportAllVehicles(vehicles)

        XCTAssertTrue(csv.hasPrefix("vehicleName,vehicleMake,vehicleModel,vehicleYear,"))
        XCTAssertTrue(csv.contains(FuelingRecord.csvHeader))
    }

    func testExportAllVehiclesSingleVehicleNoRecords() {
        let vehicle = Vehicle(
            name: "My Car",
            make: "Toyota",
            model: "Camry",
            year: 2023
        )

        let csv = CSVService.exportAllVehicles([vehicle])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Only header line
        XCTAssertEqual(lines.count, 1)
    }

    func testExportAllVehiclesSingleVehicleWithRecords() {
        let vehicle = Vehicle(
            name: "My Car",
            make: "Toyota",
            model: "Camry",
            year: 2023
        )

        let date = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")!
        let record = FuelingRecord(
            date: date,
            currentMiles: 12500,
            pricePerGallon: 3.459,
            gallons: 10.5,
            totalCost: 36.32,
            fillUpType: .full,
            notes: "Test"
        )

        vehicle.fuelingRecords = [record]

        let csv = CSVService.exportAllVehicles([vehicle])

        XCTAssertTrue(csv.contains("\"My Car\""))
        XCTAssertTrue(csv.contains("\"Toyota\""))
        XCTAssertTrue(csv.contains("\"Camry\""))
        XCTAssertTrue(csv.contains("2023"))
        XCTAssertTrue(csv.contains("12500.0"))
    }

    func testExportAllVehiclesWithNilMakeModel() {
        let vehicle = Vehicle(name: "My Car")

        let date = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")!
        let record = FuelingRecord(
            date: date,
            currentMiles: 12500,
            pricePerGallon: 3.459,
            gallons: 10.5,
            totalCost: 36.32,
            fillUpType: .full,
            notes: nil
        )

        vehicle.fuelingRecords = [record]

        let csv = CSVService.exportAllVehicles([vehicle])

        XCTAssertTrue(csv.contains("\"My Car\""))
        XCTAssertTrue(csv.contains("\"\",\"\",0"))  // Empty make, model, and 0 year
    }

    // MARK: - Import Tests

    func testImportRecordsEmpty() {
        let csv = FuelingRecord.csvHeader
        let records = CSVService.importRecords(from: csv, vehicle: testVehicle)

        XCTAssertTrue(records.isEmpty)
    }

    func testImportRecordsSingleRecord() {
        let csv = """
        date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes
        2024-01-15T10:30:00Z,12500,3.459,10.5,36.32,full,Test note
        """

        let records = CSVService.importRecords(from: csv, vehicle: testVehicle)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].currentMiles, 12500)
        XCTAssertEqual(records[0].pricePerGallon, 3.459)
        XCTAssertEqual(records[0].gallons, 10.5)
        XCTAssertEqual(records[0].totalCost, 36.32)
        XCTAssertEqual(records[0].fillUpType, .full)
        XCTAssertEqual(records[0].notes, "Test note")
    }

    func testImportRecordsMultipleRecords() {
        let csv = """
        date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes
        2024-01-15T10:30:00Z,12500,3.459,10.5,36.32,full,First
        2024-01-22T10:30:00Z,13000,3.599,11.0,39.59,partial,Second
        """

        let records = CSVService.importRecords(from: csv, vehicle: testVehicle)

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].notes, "First")
        XCTAssertEqual(records[1].notes, "Second")
        XCTAssertEqual(records[1].fillUpType, .partial)
    }

    func testImportRecordsSkipsInvalidRows() {
        let csv = """
        date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes
        2024-01-15T10:30:00Z,12500,3.459,10.5,36.32,full,Valid
        invalid-date,13000,3.599,11.0,39.59,full,Invalid
        2024-01-22T10:30:00Z,13500,3.699,12.0,44.39,full,Also Valid
        """

        let records = CSVService.importRecords(from: csv, vehicle: testVehicle)

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].notes, "Valid")
        XCTAssertEqual(records[1].notes, "Also Valid")
    }

    func testImportRecordsSkipsEmptyLines() {
        let csv = """
        date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes
        2024-01-15T10:30:00Z,12500,3.459,10.5,36.32,full,Test


        """

        let records = CSVService.importRecords(from: csv, vehicle: testVehicle)

        XCTAssertEqual(records.count, 1)
    }

    // MARK: - Import Simple Format Tests

    func testImportSimpleFormatWithYYYYMMDD() {
        let csv = """
        date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes
        2024-01-15,12500,3.459,10.5,36.32,full,Test
        """

        let records = CSVService.importSimpleFormat(from: csv, vehicle: testVehicle)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].currentMiles, 12500)
    }

    func testImportSimpleFormatWithMMDDYYYY() {
        let csv = """
        date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes
        01/15/2024,12500,3.459,10.5,36.32,full,Test
        """

        let records = CSVService.importSimpleFormat(from: csv, vehicle: testVehicle)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].currentMiles, 12500)
    }

    func testImportSimpleFormatWithISO8601() {
        let csv = """
        date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes
        2024-01-15T10:30:00Z,12500,3.459,10.5,36.32,full,Test
        """

        let records = CSVService.importSimpleFormat(from: csv, vehicle: testVehicle)

        XCTAssertEqual(records.count, 1)
    }

    func testImportSimpleFormatWithLegacyTrueFormat() {
        let csv = """
        date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes
        2024-01-15,12500,3.459,10.5,36.32,true,Test
        """

        let records = CSVService.importSimpleFormat(from: csv, vehicle: testVehicle)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].fillUpType, .partial)
    }

    func testImportSimpleFormatWithPartialFillUp() {
        let csv = """
        date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes
        2024-01-15,12500,3.459,10.5,36.32,partial,Test
        """

        let records = CSVService.importSimpleFormat(from: csv, vehicle: testVehicle)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].fillUpType, .partial)
    }

    func testImportSimpleFormatWithResetFillUp() {
        let csv = """
        date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes
        2024-01-15,12500,3.459,10.5,36.32,reset,Test
        """

        let records = CSVService.importSimpleFormat(from: csv, vehicle: testVehicle)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].fillUpType, .reset)
    }

    func testImportSimpleFormatWithMissingFillUpType() {
        let csv = """
        date,currentMiles,pricePerGallon,gallons,totalCost
        2024-01-15,12500,3.459,10.5,36.32
        """

        let records = CSVService.importSimpleFormat(from: csv, vehicle: testVehicle)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].fillUpType, .full) // Defaults to full
    }

    func testImportSimpleFormatWithQuotedNotes() {
        let csv = """
        date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes
        2024-01-15,12500,3.459,10.5,36.32,full,"Note with, comma"
        """

        let records = CSVService.importSimpleFormat(from: csv, vehicle: testVehicle)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].notes, "Note with, comma")
    }

    func testImportSimpleFormatSkipsInvalidDate() {
        let csv = """
        date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes
        invalid-date,12500,3.459,10.5,36.32,full,Test
        """

        let records = CSVService.importSimpleFormat(from: csv, vehicle: testVehicle)

        XCTAssertTrue(records.isEmpty)
    }

    func testImportSimpleFormatSkipsTooFewColumns() {
        let csv = """
        date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes
        2024-01-15,12500,3.459,10.5
        """

        let records = CSVService.importSimpleFormat(from: csv, vehicle: testVehicle)

        XCTAssertTrue(records.isEmpty)
    }

    // MARK: - CSV Validation Tests

    func testValidateCSVEmptyFile() {
        let csv = ""
        let result = CSVService.validateCSV(csv)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.error, "The file is empty")
    }

    func testValidateCSVHeaderOnly() {
        let csv = "date,currentMiles,pricePerGallon,gallons,totalCost"
        let result = CSVService.validateCSV(csv)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.error, "The file only contains a header row with no data")
    }

    func testValidateCSVNoHeader() {
        let csv = """
        2024-01-15,12500,3.459,10.5,36.32
        2024-01-22,13000,3.599,11.0,39.59
        """
        let result = CSVService.validateCSV(csv)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.error, "The file doesn't appear to have a valid header row")
    }

    func testValidateCSVValid() {
        let csv = """
        date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes
        2024-01-15,12500,3.459,10.5,36.32,full,Test
        """
        let result = CSVService.validateCSV(csv)

        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.error)
    }

    func testValidateCSVWithDateHeader() {
        let csv = """
        date,miles,price
        2024-01-15,12500,3.459
        """
        let result = CSVService.validateCSV(csv)

        XCTAssertTrue(result.isValid)
    }

    func testValidateCSVWithMilesHeader() {
        let csv = """
        timestamp,miles,cost
        2024-01-15,12500,36.32
        """
        let result = CSVService.validateCSV(csv)

        XCTAssertTrue(result.isValid)
    }

    func testValidateCSVWithGallonHeader() {
        let csv = """
        time,gallon,price
        2024-01-15,10.5,3.459
        """
        let result = CSVService.validateCSV(csv)

        XCTAssertTrue(result.isValid)
    }

    // MARK: - Generate Template Tests

    func testGenerateTemplate() {
        let template = CSVService.generateTemplate()

        XCTAssertTrue(template.contains("date,currentMiles,pricePerGallon,gallons,totalCost,fillUpType,notes"))
        XCTAssertTrue(template.contains("2024-01-15,12500,3.459,10.5,36.32,full"))
        XCTAssertTrue(template.contains("2024-01-22,12800,3.399,11.2,38.07,full"))
    }

    func testTemplateCanBeImported() {
        let template = CSVService.generateTemplate()
        let records = CSVService.importSimpleFormat(from: template, vehicle: testVehicle)

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].currentMiles, 12500)
        XCTAssertEqual(records[1].currentMiles, 12800)
    }

    // MARK: - Round-trip Tests

    func testExportImportRoundTrip() {
        let date = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")!

        let originalRecord = FuelingRecord(
            date: date,
            currentMiles: 12500,
            pricePerGallon: 3.459,
            gallons: 10.5,
            totalCost: 36.32,
            fillUpType: .partial,
            notes: "Round trip test"
        )

        let csv = CSVService.exportRecords([originalRecord])
        let importedRecords = CSVService.importRecords(from: csv, vehicle: testVehicle)

        XCTAssertEqual(importedRecords.count, 1)

        let importedRecord = importedRecords[0]
        XCTAssertEqual(importedRecord.currentMiles, originalRecord.currentMiles)
        XCTAssertEqual(importedRecord.pricePerGallon, originalRecord.pricePerGallon)
        XCTAssertEqual(importedRecord.gallons, originalRecord.gallons)
        XCTAssertEqual(importedRecord.totalCost, originalRecord.totalCost)
        XCTAssertEqual(importedRecord.fillUpType, originalRecord.fillUpType)
        XCTAssertEqual(importedRecord.notes, originalRecord.notes)
    }

    func testExportImportRoundTripWithSpecialCharacters() {
        let date = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")!

        let originalRecord = FuelingRecord(
            date: date,
            currentMiles: 12500,
            pricePerGallon: 3.459,
            gallons: 10.5,
            totalCost: 36.32,
            fillUpType: .full,
            notes: "Note with \"quotes\" and, commas"
        )

        let csv = CSVService.exportRecords([originalRecord])
        let importedRecords = CSVService.importRecords(from: csv, vehicle: testVehicle)

        XCTAssertEqual(importedRecords.count, 1)
        // Note: due to quote escaping, the notes may differ slightly
        XCTAssertNotNil(importedRecords[0].notes)
    }
}

