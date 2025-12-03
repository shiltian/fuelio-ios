import SwiftUI
import SwiftData

struct AddRecordView: View {
    let vehicle: Vehicle
    let onSave: ((FuelingRecord) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Form fields
    @State private var date = Date()
    @State private var currentMilesString = ""
    @State private var pricePerGallonString = ""
    @State private var gallonsString = ""
    @State private var totalCostString = ""
    @State private var isPartialFillUp = false
    @State private var notes = ""

    // Track which field to calculate (the one NOT being edited)
    // We track the two most recently user-edited fields; the third gets calculated
    @State private var userEditedFields: [EditableField] = []
    @FocusState private var focusedField: EditableField?
    @State private var isCalculating = false  // Prevent recursive calculation

    enum EditableField: Equatable {
        case pricePerGallon
        case gallons
        case totalCost
    }

    init(vehicle: Vehicle, onSave: ((FuelingRecord) -> Void)? = nil) {
        self.vehicle = vehicle
        self.onSave = onSave
    }

    // Previous miles from last record
    private var previousMiles: Double {
        vehicle.lastRecord?.currentMiles ?? 0
    }

    // Check if this is the first record (no previous records exist)
    private var isFirstRecord: Bool {
        vehicle.lastRecord == nil
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
        guard let current = currentMiles, current > previousMiles else { return false }
        guard let price = pricePerGallon, price > 0 else { return false }
        guard let gal = gallons, gal > 0 else { return false }
        guard let cost = totalCost, cost > 0 else { return false }
        return true
    }

    // Calculated preview values
    private var previewMPG: Double? {
        guard let current = currentMiles, let gal = gallons, gal > 0 else { return nil }
        let miles = current - previousMiles
        return miles / gal
    }

    private var previewCostPerMile: Double? {
        guard let current = currentMiles, let cost = totalCost else { return nil }
        let miles = current - previousMiles
        guard miles > 0 else { return nil }
        return cost / miles
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
                        Text("Previous Miles")
                            .font(.custom("Avenir Next", size: 16))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(previousMiles.formatted(.number.precision(.fractionLength(0))))
                            .font(.custom("Avenir Next", size: 16))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Current Miles")
                            .font(.custom("Avenir Next", size: 16))
                        Spacer()
                        TextField("Odometer", text: $currentMilesString)
                            .font(.custom("Avenir Next", size: 16))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }

                    if let current = currentMiles, current > previousMiles {
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
                    if currentMiles != nil && currentMiles! <= previousMiles {
                        Text("Current miles must be greater than previous miles")
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
                        TextField("0.000", text: $pricePerGallonString)
                            .font(.custom("Avenir Next", size: 16))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .focused($focusedField, equals: .pricePerGallon)
                            .onChange(of: pricePerGallonString) { _, _ in
                                fieldEdited(.pricePerGallon)
                            }
                    }

                    HStack {
                        Text("Gallons")
                            .font(.custom("Avenir Next", size: 16))
                        Spacer()
                        TextField("0.00", text: $gallonsString)
                            .font(.custom("Avenir Next", size: 16))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .focused($focusedField, equals: .gallons)
                            .onChange(of: gallonsString) { _, _ in
                                fieldEdited(.gallons)
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
                        TextField("0.00", text: $totalCostString)
                            .font(.custom("Avenir Next", size: 16))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .focused($focusedField, equals: .totalCost)
                            .onChange(of: totalCostString) { _, _ in
                                fieldEdited(.totalCost)
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
                if isFirstRecord {
                    // Show notice for first record instead of MPG preview
                    Section {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("This is your first fill-up. It sets your baseline odometer. MPG will be calculated from your next fill-up.")
                                .font(.custom("Avenir Next", size: 14))
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Note")
                            .font(.custom("Avenir Next", size: 12))
                    }
                } else if previewMPG != nil || previewCostPerMile != nil {
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

                // Options Section
                Section {
                    Toggle(isOn: $isPartialFillUp) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text("Partial Fill-up")
                                .font(.custom("Avenir Next", size: 16))
                        }
                    }
                } footer: {
                    Text("Mark if you didn't fill the tank completely. MPG calculations will be less accurate for partial fill-ups.")
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
            // Only 1 field edited - wait for second field or use default logic
            // Default: if price and gallons exist, calculate cost
            // if price and cost exist, calculate gallons
            // if gallons and cost exist, calculate price
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
                gallonsString = String(format: "%.2f", calculated)
            }
        case .pricePerGallon:
            if let g = gal, g > 0, let c = cost, c > 0 {
                let calculated = c / g
                pricePerGallonString = String(format: "%.3f", calculated)
            }
        }
    }

    private func saveRecord() {
        guard let current = currentMiles,
              let price = pricePerGallon,
              let gal = gallons,
              let cost = totalCost else { return }

        let record = FuelingRecord(
            date: date,
            currentMiles: current,
            previousMiles: previousMiles,
            pricePerGallon: price,
            gallons: gal,
            totalCost: cost,
            isPartialFillUp: isPartialFillUp,
            isInitialRecord: isFirstRecord,  // First record sets baseline, MPG won't be calculated
            notes: notes.isEmpty ? nil : notes
        )

        record.vehicle = vehicle
        modelContext.insert(record)

        onSave?(record)
        dismiss()
    }
}

#Preview {
    AddRecordView(vehicle: Vehicle(name: "Test Car"))
        .modelContainer(for: [Vehicle.self, FuelingRecord.self], inMemory: true)
}

