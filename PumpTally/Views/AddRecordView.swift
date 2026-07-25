import SwiftUI
import SwiftData

struct AddRecordView: View {
    let vehicle: Vehicle
    let onSave: ((FuelingRecord, Double) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage private var metricEfficiencyFormatRaw: String

    private var units: UnitSystem { vehicle.unitSystem }

    private var metricEfficiencyFormat: MetricEfficiencyFormat {
        MetricEfficiencyFormat(rawValue: metricEfficiencyFormatRaw) ?? .defaultFormat
    }

    // Form fields
    @State private var date = Date()
    @State private var odometerString = ""
    @State private var pricePerFuelUnitMills: Int = 0
    @State private var fuelAmountMills: Int = 0
    @State private var totalCostCents: Int = 0
    @State private var fillUpType: FillUpType = .full
    @State private var notes = ""
    @State private var previousOdometer: Double

    @FocusState private var focusedField: FuelingRecordFormView.EditableField?

    init(vehicle: Vehicle, onSave: ((FuelingRecord, Double) -> Void)? = nil) {
        self.vehicle = vehicle
        self.onSave = onSave
        _metricEfficiencyFormatRaw = AppStorage(
            wrappedValue: MetricEfficiencyFormat.defaultFormat.rawValue,
            MetricEfficiencyFormat.storageKey(for: vehicle.id)
        )
        _previousOdometer = State(initialValue: vehicle.lastRecord?.odometer ?? 0)
    }

    // Parsed values for validation
    private var currentOdometer: Double? { Double(odometerString) }
    private var pricePerFuelUnit: Double { Double(pricePerFuelUnitMills) / 1000.0 }
    private var fuelAmount: Double { Double(fuelAmountMills) / 1000.0 }
    private var totalCost: Double { Double(totalCostCents) / 100.0 }

    private var isValid: Bool {
        guard let current = currentOdometer, current > previousOdometer else { return false }
        guard pricePerFuelUnit > 0 else { return false }
        guard fuelAmount > 0 else { return false }
        guard totalCost > 0 else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                FuelingRecordFormView(
                    unitSystem: units,
                    metricEfficiencyFormat: metricEfficiencyFormat,
                    date: $date,
                    odometerString: $odometerString,
                    pricePerFuelUnitMills: $pricePerFuelUnitMills,
                    fuelAmountMills: $fuelAmountMills,
                    totalCostCents: $totalCostCents,
                    fillUpType: $fillUpType,
                    notes: $notes,
                    focusedField: $focusedField,
                    previousOdometer: previousOdometer,
                    showPreview: true
                )
            }
            .navigationTitle("Add Fueling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRecord() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }

                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            focusedField = nil
                            hideKeyboard()
                        }
                    }
                }
            }
        }
    }

    private func saveRecord() {
        guard let current = currentOdometer else { return }

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

        record.modifiedAt = Date()
        modelContext.insert(record)

        // Force an immediate save so SwiftData processes the inverse
        // relationship (vehicle.fuelingRecords) right away. Without this,
        // the auto-save can be deferred for seconds, causing HistoryView
        // to appear stale.
        try? modelContext.save()

        StatisticsCacheService.updateForNewRecord(record, vehicle: vehicle)
        try? modelContext.save()
        onSave?(record, previousOdometer)
        dismiss()
    }
}

#Preview {
    AddRecordView(vehicle: Vehicle(name: "Test Car"))
        .modelContainer(for: [Vehicle.self, FuelingRecord.self], inMemory: true)
}
