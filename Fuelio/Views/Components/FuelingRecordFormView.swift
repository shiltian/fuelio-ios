import SwiftUI

/// Shared form sections used by both AddRecordView and EditRecordView.
/// This eliminates duplication of the date, odometer, fuel, fill-up type,
/// preview, and notes sections.
struct FuelingRecordFormView: View {
    let unitSystem: UnitSystem

    @Binding var date: Date
    @Binding var odometerString: String
    @Binding var pricePerFuelUnitMills: Int
    @Binding var fuelAmountMills: Int
    @Binding var totalCostCents: Int
    @Binding var fillUpType: FillUpType
    @Binding var notes: String

    var focusedField: FocusState<EditableField?>.Binding

    /// Previous odometer reading — zero means first record, hides distance/preview
    var previousOdometer: Double = 0

    /// Whether to show the preview section (AddRecordView uses it, EditRecordView does not)
    var showPreview: Bool = true

    enum EditableField: Equatable {
        case pricePerFuelUnit
        case fuelAmount
        case totalCost
    }

    // MARK: - Computed Values

    private var currentOdometer: Double? { Double(odometerString) }
    private var pricePerFuelUnit: Double { Double(pricePerFuelUnitMills) / 1000.0 }
    private var fuelAmount: Double { Double(fuelAmountMills) / 1000.0 }
    private var totalCost: Double { Double(totalCostCents) / 100.0 }

    private var previewEfficiency: Double? {
        guard showPreview, let current = currentOdometer, fuelAmount > 0 else { return nil }
        let distance = current - previousOdometer
        guard distance > 0 else { return nil }
        return unitSystem.efficiencyDisplayValue(from: distance / fuelAmount)
    }

    private var previewCostPerDistance: Double? {
        guard showPreview, let current = currentOdometer, totalCost > 0 else { return nil }
        let distance = current - previousOdometer
        guard distance > 0 else { return nil }
        return totalCost / distance
    }

    var body: some View {
        dateSection
        odometerSection
        fuelSection
        if showPreview {
            previewSection
        }
        fillUpTypeSection
        notesSection
    }

    // MARK: - Date Section

    private var dateSection: some View {
        Section {
            DatePicker("Date & Time", selection: $date, in: ...Date())
                .font(.appBody)
        } header: {
            Text("When")
                .font(.appCaption)
        }
    }

    // MARK: - Odometer Section

    private var odometerSection: some View {
        Section {
            HStack {
                Text("Odometer Reading")
                    .font(.appBody)
                Spacer()
                TextField(unitSystem.distanceUnit, text: $odometerString)
                    .font(.appBody)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
            }

            if previousOdometer > 0, let current = currentOdometer, current > previousOdometer {
                HStack {
                    Text("\(unitSystem.distanceName) This Trip")
                        .font(.appBody)
                        .foregroundColor(.teal)
                    Spacer()
                    Text((current - previousOdometer).formatted(.number.precision(.fractionLength(0))))
                        .font(.appBody)
                        .fontWeight(.semibold)
                        .foregroundColor(.teal)
                }
            }
        } header: {
            Text("Odometer")
                .font(.appCaption)
        } footer: {
            if previousOdometer > 0, let current = currentOdometer, current <= previousOdometer {
                Text("Odometer must be greater than last recorded (\(previousOdometer.formatted(.number.precision(.fractionLength(0)))) \(unitSystem.distanceUnit))")
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Fuel Section

    private var fuelSection: some View {
        Section {
            HStack {
                Text(unitSystem.pricePerFuelLabel)
                    .font(.appBody)
                Spacer()
                Text("$")
                    .foregroundColor(.secondary)
                CurrencyInputField(
                    value: $pricePerFuelUnitMills,
                    decimalPlaces: 3,
                    width: 100
                )
                .focused(focusedField, equals: .pricePerFuelUnit)
                .onChange(of: pricePerFuelUnitMills) { _, _ in
                    if focusedField.wrappedValue == .pricePerFuelUnit { calculateFuelAmount() }
                }
            }

            HStack {
                Text(unitSystem.fuelName)
                    .font(.appBody)
                Spacer()
                CurrencyInputField(
                    value: $fuelAmountMills,
                    decimalPlaces: 3,
                    width: 100
                )
                .focused(focusedField, equals: .fuelAmount)
                .onChange(of: fuelAmountMills) { _, _ in
                    if focusedField.wrappedValue == .fuelAmount { calculatePricePerFuelUnit() }
                }
                Text(unitSystem.fuelUnit)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Total Cost")
                    .font(.appBody)
                Spacer()
                Text("$")
                    .foregroundColor(.secondary)
                CurrencyInputField(
                    value: $totalCostCents,
                    decimalPlaces: 2,
                    width: 100
                )
                .focused(focusedField, equals: .totalCost)
                .onChange(of: totalCostCents) { _, _ in
                    if focusedField.wrappedValue == .totalCost { calculatePricePerFuelUnit() }
                }
            }
        } header: {
            Text("Fuel Details")
                .font(.appCaption)
        } footer: {
            Text("Enter any 2 fields and the third will be calculated automatically")
                .font(.appCaption)
        }
    }

    // MARK: - Preview Section

    @ViewBuilder
    private var previewSection: some View {
        if previousOdometer > 0, previewEfficiency != nil || previewCostPerDistance != nil {
            Section {
                if let efficiency = previewEfficiency {
                    HStack {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .foregroundColor(.purple)
                        Text("Estimated \(unitSystem.efficiencyUnit)")
                            .font(.appBody)
                        Spacer()
                        Text("\(efficiency.formatted(.number.precision(.fractionLength(1)))) \(unitSystem.efficiencyUnit)")
                            .font(.appBody)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)
                    }
                }

                if let cpd = previewCostPerDistance {
                    HStack {
                        Image(systemName: "dollarsign.circle")
                            .foregroundColor(.orange)
                        Text(unitSystem.costPerDistanceLabel)
                            .font(.appBody)
                        Spacer()
                        Text(cpd.currencyFormatted)
                            .font(.appBody)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                }
            } header: {
                Text("Preview")
                    .font(.appCaption)
            }
        }
    }

    // MARK: - Fill-Up Type Section

    private var fillUpTypeSection: some View {
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
            .font(.appBody)
            .pickerStyle(.menu)
        } footer: {
            Text(fillUpType.description)
                .font(.appCaption)
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        Section {
            TextField("Add notes (optional)", text: $notes, axis: .vertical)
                .font(.appBody)
                .lineLimit(3...6)
        } header: {
            Text("Notes")
                .font(.appCaption)
        }
    }

    // MARK: - Auto-Calculation

    private func calculatePricePerFuelUnit() {
        guard fuelAmount > 0, totalCost > 0 else { return }
        let calculated = totalCost / fuelAmount
        pricePerFuelUnitMills = Int(round(calculated * 1000))
    }

    private func calculateFuelAmount() {
        guard pricePerFuelUnit > 0, totalCost > 0 else { return }
        let calculated = totalCost / pricePerFuelUnit
        fuelAmountMills = Int(round(calculated * 1000))
    }
}
