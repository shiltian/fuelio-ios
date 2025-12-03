import SwiftUI
import SwiftData

struct EditRecordView: View {
    @Bindable var record: FuelingRecord
    let vehicle: Vehicle

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Form fields
    @State private var date: Date
    @State private var currentMilesString: String
    @State private var pricePerGallonString: String
    @State private var gallonsString: String
    @State private var totalCostString: String
    @State private var fillUpType: FillUpType
    @State private var notes: String

    @FocusState private var focusedField: EditableField?
    @State private var userEditedFields: [EditableField] = []
    @State private var isCalculating = false

    enum EditableField: Equatable {
        case pricePerGallon
        case gallons
        case totalCost
    }

    init(record: FuelingRecord, vehicle: Vehicle) {
        self.record = record
        self.vehicle = vehicle
        _date = State(initialValue: record.date)
        _currentMilesString = State(initialValue: String(format: "%.0f", record.currentMiles))
        _pricePerGallonString = State(initialValue: String(format: "%.3f", record.pricePerGallon))
        _gallonsString = State(initialValue: String(format: "%.3f", record.gallons))
        _totalCostString = State(initialValue: String(format: "%.2f", record.totalCost))
        _fillUpType = State(initialValue: record.fillUpType)
        _notes = State(initialValue: record.notes ?? "")
    }

    // Parsed values
    private var currentMiles: Double? {
        Double(currentMilesString)
    }

    private var pricePerGallon: Double? {
        Double(pricePerGallonString)
    }

    private var gallons: Double? {
        Double(gallonsString)
    }

    private var totalCost: Double? {
        Double(totalCostString)
    }

    // Validation
    private var isValid: Bool {
        guard let _ = currentMiles else { return false }
        guard let price = pricePerGallon, price > 0 else { return false }
        guard let gal = gallons, gal > 0 else { return false }
        guard let cost = totalCost, cost > 0 else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                // Date Section
                Section {
                    DatePicker("Date & Time", selection: $date, in: ...Date())
                        .font(.custom("Avenir Next", size: 16))
                } header: {
                    Text("When")
                        .font(.custom("Avenir Next", size: 12))
                }

                // Odometer Section
                Section {
                    HStack {
                        Text("Odometer Reading")
                            .font(.custom("Avenir Next", size: 16))
                        Spacer()
                        TextField("Miles", text: $currentMilesString)
                            .font(.custom("Avenir Next", size: 16))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                } header: {
                    Text("Odometer")
                        .font(.custom("Avenir Next", size: 12))
                }

                // Fuel Section
                Section {
                    HStack {
                        Text("Price per Gallon")
                            .font(.custom("Avenir Next", size: 16))
                        Spacer()
                        Text("$")
                            .foregroundColor(.secondary)
                        TextField("0.000", text: $pricePerGallonString)
                            .font(.custom("Avenir Next", size: 16))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .focused($focusedField, equals: .pricePerGallon)
                            .onChange(of: pricePerGallonString) { _, _ in fieldEdited(.pricePerGallon) }
                    }

                    HStack {
                        Text("Gallons")
                            .font(.custom("Avenir Next", size: 16))
                        Spacer()
                        TextField("0.000", text: $gallonsString)
                            .font(.custom("Avenir Next", size: 16))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .focused($focusedField, equals: .gallons)
                            .onChange(of: gallonsString) { _, _ in fieldEdited(.gallons) }
                        Text("gal")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Total Cost")
                            .font(.custom("Avenir Next", size: 16))
                        Spacer()
                        Text("$")
                            .foregroundColor(.secondary)
                        TextField("0.00", text: $totalCostString)
                            .font(.custom("Avenir Next", size: 16))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .focused($focusedField, equals: .totalCost)
                            .onChange(of: totalCostString) { _, _ in fieldEdited(.totalCost) }
                    }
                } header: {
                    Text("Fuel Details")
                        .font(.custom("Avenir Next", size: 12))
                }

                // Fill-up Type Section
                Section {
                    Picker("Fill-up Type", selection: $fillUpType) {
                        ForEach(FillUpType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                    .foregroundColor(type.color)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    .font(.custom("Avenir Next", size: 16))
                    .pickerStyle(.menu)
                } footer: {
                    Text(fillUpType.description)
                        .font(.custom("Avenir Next", size: 12))
                }

                // Notes Section
                Section {
                    TextField("Add notes (optional)", text: $notes, axis: .vertical)
                        .font(.custom("Avenir Next", size: 16))
                        .lineLimit(3...6)
                } header: {
                    Text("Notes")
                        .font(.custom("Avenir Next", size: 12))
                }
            }
            .navigationTitle("Edit Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }

                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            focusedField = nil
                        }
                    }
                }
            }
        }
    }

    private func fieldEdited(_ field: EditableField) {
        // Prevent recursive calls when we programmatically set values
        guard !isCalculating else { return }

        // Track user-edited fields (keep last 2)
        if userEditedFields.last != field {
            userEditedFields.append(field)
            if userEditedFields.count > 2 {
                userEditedFields.removeFirst()
            }
        }

        autoCalculate()
    }

    private func autoCalculate() {
        // Need at least one user-edited field to know what to calculate
        guard !userEditedFields.isEmpty else { return }

        let price = pricePerGallon
        let gal = gallons
        let cost = totalCost

        // Determine which field to calculate (the one not recently edited by user)
        let fieldToCalculate: EditableField
        if userEditedFields.count >= 2 {
            // We have 2 user-edited fields, calculate the third
            let allFields: Set<EditableField> = [.pricePerGallon, .gallons, .totalCost]
            let editedSet = Set(userEditedFields.suffix(2))
            if let remaining = allFields.subtracting(editedSet).first {
                fieldToCalculate = remaining
            } else {
                return
            }
        } else {
            // Only 1 field edited - use default logic based on which fields have values
            if let p = price, p > 0, let g = gal, g > 0, (cost == nil || cost == 0) {
                fieldToCalculate = .totalCost
            } else if let p = price, p > 0, let c = cost, c > 0, (gal == nil || gal == 0) {
                fieldToCalculate = .gallons
            } else if let g = gal, g > 0, let c = cost, c > 0, (price == nil || price == 0) {
                fieldToCalculate = .pricePerGallon
            } else {
                return
            }
        }

        // Perform the calculation
        isCalculating = true
        defer { isCalculating = false }

        switch fieldToCalculate {
        case .totalCost:
            if let p = price, p > 0, let g = gal, g > 0 {
                let calculated = p * g
                totalCostString = String(format: "%.2f", calculated)
            }
        case .gallons:
            if let p = price, p > 0, let c = cost, c > 0 {
                let calculated = c / p
                gallonsString = String(format: "%.3f", calculated)
            }
        case .pricePerGallon:
            if let g = gal, g > 0, let c = cost, c > 0 {
                let calculated = c / g
                pricePerGallonString = String(format: "%.3f", calculated)
            }
        }
    }

    private func saveChanges() {
        guard let current = currentMiles,
              let price = pricePerGallon,
              let gal = gallons,
              let cost = totalCost else { return }

        record.date = date
        record.currentMiles = current
        record.pricePerGallon = price
        record.gallons = gal
        record.totalCost = cost
        record.fillUpType = fillUpType
        record.notes = notes.isEmpty ? nil : notes

        // Full recalculation on edit (as agreed - edits are less frequent)
        StatisticsCacheService.updateForEditedRecord(vehicle: vehicle)

        dismiss()
    }

}

#Preview {
    let record = FuelingRecord(
        currentMiles: 1000,
        pricePerGallon: 3.459,
        gallons: 12.5,
        totalCost: 43.24
    )
    let vehicle = Vehicle(name: "Test Car")

    return EditRecordView(record: record, vehicle: vehicle)
        .modelContainer(for: [Vehicle.self, FuelingRecord.self], inMemory: true)
}

