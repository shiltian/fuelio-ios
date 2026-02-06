import SwiftUI
import SwiftData

struct AddRecordView: View {
    let vehicle: Vehicle
    let onSave: ((FuelingRecord, Double) -> Void)?  // (record, previousOdometer)

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var units: UnitSystem { vehicle.unitSystem }

    // Form fields
    @State private var date = Date()
    @State private var odometerString = ""
    // Store as integers (cents/mills) for right-to-left entry
    @State private var pricePerFuelUnitMills: Int = 0   // 3 decimal places
    @State private var fuelAmountMills: Int = 0          // 3 decimal places
    @State private var totalCostCents: Int = 0        // 2 decimal places
    @State private var fillUpType: FillUpType = .full
    @State private var notes = ""

    @FocusState private var focusedField: EditableField?
    @State private var isCalculating = false  // Prevent recursive calculation

    enum EditableField: Equatable {
        case pricePerFuelUnit
        case fuelAmount
        case totalCost
    }

    init(vehicle: Vehicle, onSave: ((FuelingRecord, Double) -> Void)? = nil) {
        self.vehicle = vehicle
        self.onSave = onSave
    }

    // Previous odometer from last record
    private var previousOdometer: Double {
        vehicle.lastRecord?.odometer ?? 0
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
        guard let current = currentOdometer, current > previousOdometer else { return false }
        guard pricePerFuelUnit > 0 else { return false }
        guard fuelAmount > 0 else { return false }
        guard totalCost > 0 else { return false }
        return true
    }

    // Calculated preview values
    private var previewEfficiency: Double? {
        guard let current = currentOdometer, fuelAmount > 0 else { return nil }
        let distance = current - previousOdometer
        guard distance > 0 else { return nil }
        let rawRatio = distance / fuelAmount
        return units.efficiencyDisplayValue(from: rawRatio)
    }

    private var previewCostPerDistance: Double? {
        guard let current = currentOdometer, totalCost > 0 else { return nil }
        let distance = current - previousOdometer
        guard distance > 0 else { return nil }
        return totalCost / distance
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

                    if previousOdometer > 0, let current = currentOdometer, current > previousOdometer {
                        HStack {
                            Text("\(units.distanceName) This Trip")
                                .font(.custom("Avenir Next", size: 16))
                                .foregroundColor(.teal)
                            Spacer()
                            Text((current - previousOdometer).formatted(.number.precision(.fractionLength(0))))
                                .font(.custom("Avenir Next", size: 16))
                                .fontWeight(.semibold)
                                .foregroundColor(.teal)
                        }
                    }
                } header: {
                    Text("Odometer")
                        .font(.custom("Avenir Next", size: 12))
                } footer: {
                    if previousOdometer > 0 && currentOdometer != nil && currentOdometer! <= previousOdometer {
                        Text("Odometer must be greater than last recorded (\(previousOdometer.formatted(.number.precision(.fractionLength(0)))) \(units.distanceUnit))")
                            .foregroundColor(.red)
                    }
                }

                // Fuel Section with Auto-Calculate
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
                } footer: {
                    Text("Enter any 2 fields and the third will be calculated automatically")
                        .font(.custom("Avenir Next", size: 12))
                }

                // Preview Section
                if previousOdometer > 0 && (previewEfficiency != nil || previewCostPerDistance != nil) {
                    Section {
                        if let efficiency = previewEfficiency {
                            HStack {
                                Image(systemName: "gauge.with.dots.needle.67percent")
                                    .foregroundColor(.purple)
                                Text("Estimated \(units.efficiencyUnit)")
                                    .font(.custom("Avenir Next", size: 16))
                                Spacer()
                                Text("\(efficiency.formatted(.number.precision(.fractionLength(1)))) \(units.efficiencyUnit)")
                                    .font(.custom("Avenir Next", size: 16))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.purple)
                            }
                        }

                        if let cpd = previewCostPerDistance {
                            HStack {
                                Image(systemName: "dollarsign.circle")
                                    .foregroundColor(.orange)
                                Text(units.costPerDistanceLabel)
                                    .font(.custom("Avenir Next", size: 16))
                                Spacer()
                                Text(cpd.currencyFormatted)
                                    .font(.custom("Avenir Next", size: 16))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            }
                        }
                    } header: {
                        Text("Preview")
                            .font(.custom("Avenir Next", size: 12))
                    }
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
            .navigationTitle("Add Fueling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveRecord()
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
        // Convert to mills (3 decimal places)
        pricePerFuelUnitMills = Int(round(calculated * 1000))
    }

    private func calculateFuelAmount() {
        guard !isCalculating else { return }
        guard pricePerFuelUnit > 0, totalCost > 0 else { return }

        isCalculating = true
        defer { isCalculating = false }

        let calculated = totalCost / pricePerFuelUnit
        // Convert to mills (3 decimal places)
        fuelAmountMills = Int(round(calculated * 1000))
    }

    private func saveRecord() {
        guard let current = currentOdometer else { return }

        // First record (no previous odometer) is always treated as partial since we can't calculate efficiency
        let isFirstRecord = previousOdometer == 0
        let effectiveFillUpType: FillUpType = isFirstRecord ? .partial : fillUpType

        let record = FuelingRecord(
            date: date,
            odometer: current,
            pricePerFuelUnit: pricePerFuelUnit,
            fuelAmount: fuelAmount,
            totalCost: totalCost,
            fillUpType: effectiveFillUpType,
            notes: notes.isEmpty ? nil : notes,
            vehicle: vehicle
        )

        modelContext.insert(record)

        // Update statistics cache incrementally
        StatisticsCacheService.updateForNewRecord(record, vehicle: vehicle)

        onSave?(record, previousOdometer)
        dismiss()
    }

}

#Preview {
    AddRecordView(vehicle: Vehicle(name: "Test Car"))
        .modelContainer(for: [Vehicle.self, FuelingRecord.self], inMemory: true)
}
