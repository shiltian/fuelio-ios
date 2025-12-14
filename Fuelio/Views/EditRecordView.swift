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
    // Store as integers (cents/mills) for right-to-left entry
    @State private var pricePerGallonMills: Int   // 3 decimal places
    @State private var gallonsMills: Int          // 3 decimal places
    @State private var totalCostCents: Int        // 2 decimal places
    @State private var fillUpType: FillUpType
    @State private var notes: String

    @FocusState private var focusedField: EditableField?
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
        // Convert Double to Int (mills/cents)
        _pricePerGallonMills = State(initialValue: Int(round(record.pricePerGallon * 1000)))
        _gallonsMills = State(initialValue: Int(round(record.gallons * 1000)))
        _totalCostCents = State(initialValue: Int(round(record.totalCost * 100)))
        _fillUpType = State(initialValue: record.fillUpType)
        _notes = State(initialValue: record.notes ?? "")
    }

    // Parsed values
    private var currentMiles: Double? {
        Double(currentMilesString)
    }

    private var pricePerGallon: Double {
        Double(pricePerGallonMills) / 1000.0
    }

    private var gallons: Double {
        Double(gallonsMills) / 1000.0
    }

    private var totalCost: Double {
        Double(totalCostCents) / 100.0
    }

    // Validation
    private var isValid: Bool {
        guard let _ = currentMiles else { return false }
        guard pricePerGallon > 0 else { return false }
        guard gallons > 0 else { return false }
        guard totalCost > 0 else { return false }
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
                        CurrencyInputField(
                            value: $pricePerGallonMills,
                            decimalPlaces: 3,
                            width: 100
                        )
                        .focused($focusedField, equals: .pricePerGallon)
                        .onChange(of: pricePerGallonMills) { _, _ in
                            if focusedField == .pricePerGallon { calculateGallons() }
                        }
                    }

                    HStack {
                        Text("Gallons")
                            .font(.custom("Avenir Next", size: 16))
                        Spacer()
                        CurrencyInputField(
                            value: $gallonsMills,
                            decimalPlaces: 3,
                            width: 100
                        )
                        .focused($focusedField, equals: .gallons)
                        .onChange(of: gallonsMills) { _, _ in
                            if focusedField == .gallons { calculatePricePerGallon() }
                        }
                        Text("gal")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Total Cost")
                            .font(.custom("Avenir Next", size: 16))
                        Spacer()
                        Text("$")
                            .foregroundColor(.secondary)
                        CurrencyInputField(
                            value: $totalCostCents,
                            decimalPlaces: 2,
                            width: 100
                        )
                        .focused($focusedField, equals: .totalCost)
                        .onChange(of: totalCostCents) { _, _ in
                            if focusedField == .totalCost { calculatePricePerGallon() }
                        }
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

    // Auto-calculation rules:
    // - Edit Gallons → Calculate Price/Gal (from Total Cost ÷ Gallons)
    // - Edit Total Cost → Calculate Price/Gal (from Total Cost ÷ Gallons)
    // - Edit Price/Gal → Calculate Gallons (from Total Cost ÷ Price)

    private func calculatePricePerGallon() {
        guard !isCalculating else { return }
        guard gallons > 0, totalCost > 0 else { return }

        isCalculating = true
        defer { isCalculating = false }

        let calculated = totalCost / gallons
        pricePerGallonMills = Int(round(calculated * 1000))
    }

    private func calculateGallons() {
        guard !isCalculating else { return }
        guard pricePerGallon > 0, totalCost > 0 else { return }

        isCalculating = true
        defer { isCalculating = false }

        let calculated = totalCost / pricePerGallon
        gallonsMills = Int(round(calculated * 1000))
    }

    private func saveChanges() {
        guard let current = currentMiles else { return }

        record.date = date
        record.currentMiles = current
        record.pricePerGallon = pricePerGallon
        record.gallons = gallons
        record.totalCost = totalCost
        record.fillUpType = fillUpType
        record.notes = notes.isEmpty ? nil : notes

        // Full recalculation on edit (as agreed - edits are less frequent)
        StatisticsCacheService.updateForEditedRecord(vehicle: vehicle)

        dismiss()
    }

}

#Preview {
    let vehicle = Vehicle(name: "Test Car")
        let record = FuelingRecord(
        currentMiles: 1000,
        pricePerGallon: 3.459,
        gallons: 12.5,
        totalCost: 43.24,
        vehicle: vehicle
    )

    return EditRecordView(record: record, vehicle: vehicle)
        .modelContainer(for: [Vehicle.self, FuelingRecord.self], inMemory: true)
}
