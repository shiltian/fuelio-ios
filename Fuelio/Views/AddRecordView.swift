import SwiftUI
import SwiftData

struct AddRecordView: View {
    let vehicle: Vehicle
    let onSave: ((FuelingRecord, Double) -> Void)?  // (record, previousMiles)

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Form fields
    @State private var date = Date()
    @State private var currentMilesString = ""
    // Store as integers (cents/mills) for right-to-left entry
    @State private var pricePerGallonMills: Int = 0   // 3 decimal places
    @State private var gallonsMills: Int = 0          // 3 decimal places
    @State private var totalCostCents: Int = 0        // 2 decimal places
    @State private var fillUpType: FillUpType = .full
    @State private var notes = ""

    @FocusState private var focusedField: EditableField?
    @State private var isCalculating = false  // Prevent recursive calculation

    enum EditableField: Equatable {
        case pricePerGallon
        case gallons
        case totalCost
    }

    init(vehicle: Vehicle, onSave: ((FuelingRecord, Double) -> Void)? = nil) {
        self.vehicle = vehicle
        self.onSave = onSave
    }

    // Previous miles from last record
    private var previousMiles: Double {
        vehicle.lastRecord?.currentMiles ?? 0
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
        guard let current = currentMiles, current > previousMiles else { return false }
        guard pricePerGallon > 0 else { return false }
        guard gallons > 0 else { return false }
        guard totalCost > 0 else { return false }
        return true
    }

    // Calculated preview values
    private var previewMPG: Double? {
        guard let current = currentMiles, gallons > 0 else { return nil }
        let miles = current - previousMiles
        guard miles > 0 else { return nil }
        return miles / gallons
    }

    private var previewCostPerMile: Double? {
        guard let current = currentMiles, totalCost > 0 else { return nil }
        let miles = current - previousMiles
        guard miles > 0 else { return nil }
        return totalCost / miles
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

                    if previousMiles > 0, let current = currentMiles, current > previousMiles {
                        HStack {
                            Text("Miles This Trip")
                                .font(.custom("Avenir Next", size: 16))
                                .foregroundColor(.teal)
                            Spacer()
                            Text((current - previousMiles).formatted(.number.precision(.fractionLength(0))))
                                .font(.custom("Avenir Next", size: 16))
                                .fontWeight(.semibold)
                                .foregroundColor(.teal)
                        }
                    }
                } header: {
                    Text("Odometer")
                        .font(.custom("Avenir Next", size: 12))
                } footer: {
                    if previousMiles > 0 && currentMiles != nil && currentMiles! <= previousMiles {
                        Text("Odometer must be greater than last recorded (\(previousMiles.formatted(.number.precision(.fractionLength(0)))) mi)")
                            .foregroundColor(.red)
                    }
                }

                // Fuel Section with Auto-Calculate
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
                } footer: {
                    Text("Enter any 2 fields and the third will be calculated automatically")
                        .font(.custom("Avenir Next", size: 12))
                }

                // Preview Section
                if previousMiles > 0 && (previewMPG != nil || previewCostPerMile != nil) {
                    Section {
                        if let mpg = previewMPG {
                            HStack {
                                Image(systemName: "gauge.with.dots.needle.67percent")
                                    .foregroundColor(.purple)
                                Text("Estimated MPG")
                                    .font(.custom("Avenir Next", size: 16))
                                Spacer()
                                Text("\(mpg.formatted(.number.precision(.fractionLength(1)))) MPG")
                                    .font(.custom("Avenir Next", size: 16))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.purple)
                            }
                        }

                        if let cpm = previewCostPerMile {
                            HStack {
                                Image(systemName: "dollarsign.circle")
                                    .foregroundColor(.orange)
                                Text("Cost per Mile")
                                    .font(.custom("Avenir Next", size: 16))
                                Spacer()
                                Text(cpm.currencyFormatted)
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
    // - Edit Gallons → Calculate Price/Gal (from Total Cost ÷ Gallons)
    // - Edit Total Cost → Calculate Price/Gal (from Total Cost ÷ Gallons)
    // - Edit Price/Gal → Calculate Gallons (from Total Cost ÷ Price)

    private func calculatePricePerGallon() {
        guard !isCalculating else { return }
        guard gallons > 0, totalCost > 0 else { return }

        isCalculating = true
        defer { isCalculating = false }

        let calculated = totalCost / gallons
        // Convert to mills (3 decimal places)
        pricePerGallonMills = Int(round(calculated * 1000))
    }

    private func calculateGallons() {
        guard !isCalculating else { return }
        guard pricePerGallon > 0, totalCost > 0 else { return }

        isCalculating = true
        defer { isCalculating = false }

        let calculated = totalCost / pricePerGallon
        // Convert to mills (3 decimal places)
        gallonsMills = Int(round(calculated * 1000))
    }

    private func saveRecord() {
        guard let current = currentMiles else { return }

        // First record (no previous miles) is always treated as partial since we can't calculate MPG
        let isFirstRecord = previousMiles == 0
        let effectiveFillUpType: FillUpType = isFirstRecord ? .partial : fillUpType

        let record = FuelingRecord(
            date: date,
            currentMiles: current,
            pricePerGallon: pricePerGallon,
            gallons: gallons,
            totalCost: totalCost,
            fillUpType: effectiveFillUpType,
            notes: notes.isEmpty ? nil : notes,
            vehicle: vehicle
        )

        modelContext.insert(record)

        // Update statistics cache incrementally
        StatisticsCacheService.updateForNewRecord(record, vehicle: vehicle)

        onSave?(record, previousMiles)
        dismiss()
    }

}

#Preview {
    AddRecordView(vehicle: Vehicle(name: "Test Car"))
        .modelContainer(for: [Vehicle.self, FuelingRecord.self], inMemory: true)
}
