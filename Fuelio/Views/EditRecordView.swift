import SwiftUI
import SwiftData

struct EditRecordView: View {
    @Bindable var record: FuelingRecord
    let vehicle: Vehicle

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var units: UnitSystem { vehicle.unitSystem }

    // Form fields
    @State private var date: Date
    @State private var odometerString: String
    // Store as integers (cents/mills) for right-to-left entry
    @State private var pricePerFuelUnitMills: Int   // 3 decimal places
    @State private var fuelAmountMills: Int          // 3 decimal places
    @State private var totalCostCents: Int        // 2 decimal places
    @State private var fillUpType: FillUpType
    @State private var notes: String

    @FocusState private var focusedField: EditableField?
    @State private var isCalculating = false

    enum EditableField: Equatable {
        case pricePerFuelUnit
        case fuelAmount
        case totalCost
    }

    init(record: FuelingRecord, vehicle: Vehicle) {
        self.record = record
        self.vehicle = vehicle
        _date = State(initialValue: record.date)
        _odometerString = State(initialValue: String(format: "%.0f", record.odometer))
        // Convert Double to Int (mills/cents)
        _pricePerFuelUnitMills = State(initialValue: Int(round(record.pricePerFuelUnit * 1000)))
        _fuelAmountMills = State(initialValue: Int(round(record.fuelAmount * 1000)))
        _totalCostCents = State(initialValue: Int(round(record.totalCost * 100)))
        _fillUpType = State(initialValue: record.fillUpType)
        _notes = State(initialValue: record.notes ?? "")
    }

    // Parsed values
    private var currentOdometer: Double? {
        Double(odometerString)
    }

    private var pricePerFuelUnit: Double {
        Double(pricePerFuelUnitMills) / 1000.0
    }

    private var fuelAmount: Double {
        Double(fuelAmountMills) / 1000.0
    }

    private var totalCost: Double {
        Double(totalCostCents) / 100.0
    }

    // Validation
    private var isValid: Bool {
        guard let _ = currentOdometer else { return false }
        guard pricePerFuelUnit > 0 else { return false }
        guard fuelAmount > 0 else { return false }
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
                        TextField(units.distanceUnit, text: $odometerString)
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
                        Text(units.pricePerFuelLabel)
                            .font(.custom("Avenir Next", size: 16))
                        Spacer()
                        Text("$")
                            .foregroundColor(.secondary)
                        CurrencyInputField(
                            value: $pricePerFuelUnitMills,
                            decimalPlaces: 3,
                            width: 100
                        )
                        .focused($focusedField, equals: .pricePerFuelUnit)
                        .onChange(of: pricePerFuelUnitMills) { _, _ in
                            if focusedField == .pricePerFuelUnit { calculateFuelAmount() }
                        }
                    }

                    HStack {
                        Text(units.fuelName)
                            .font(.custom("Avenir Next", size: 16))
                        Spacer()
                        CurrencyInputField(
                            value: $fuelAmountMills,
                            decimalPlaces: 3,
                            width: 100
                        )
                        .focused($focusedField, equals: .fuelAmount)
                        .onChange(of: fuelAmountMills) { _, _ in
                            if focusedField == .fuelAmount { calculatePricePerFuelUnit() }
                        }
                        Text(units.fuelUnit)
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
                            if focusedField == .totalCost { calculatePricePerFuelUnit() }
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
    // - Edit FuelAmount → Calculate Price/Unit (from Total Cost ÷ FuelAmount)
    // - Edit Total Cost → Calculate Price/Unit (from Total Cost ÷ FuelAmount)
    // - Edit Price/Unit → Calculate FuelAmount (from Total Cost ÷ Price)

    private func calculatePricePerFuelUnit() {
        guard !isCalculating else { return }
        guard fuelAmount > 0, totalCost > 0 else { return }

        isCalculating = true
        defer { isCalculating = false }

        let calculated = totalCost / fuelAmount
        pricePerFuelUnitMills = Int(round(calculated * 1000))
    }

    private func calculateFuelAmount() {
        guard !isCalculating else { return }
        guard pricePerFuelUnit > 0, totalCost > 0 else { return }

        isCalculating = true
        defer { isCalculating = false }

        let calculated = totalCost / pricePerFuelUnit
        fuelAmountMills = Int(round(calculated * 1000))
    }

    private func saveChanges() {
        guard let current = currentOdometer else { return }

        record.date = date
        record.odometer = current
        record.pricePerFuelUnit = pricePerFuelUnit
        record.fuelAmount = fuelAmount
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
        odometer: 1000,
        pricePerFuelUnit: 3.459,
        fuelAmount: 12.5,
        totalCost: 43.24,
        vehicle: vehicle
    )

    return EditRecordView(record: record, vehicle: vehicle)
        .modelContainer(for: [Vehicle.self, FuelingRecord.self], inMemory: true)
}
