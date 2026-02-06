import SwiftUI
import SwiftData

struct AddRecordView: View {
    let vehicle: Vehicle
    let onSave: ((FuelingRecord, Double) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var units: UnitSystem { vehicle.unitSystem }

    // Form fields
    @State private var date = Date()
    @State private var odometerString = ""
    @State private var pricePerFuelUnitMills: Int = 0
    @State private var fuelAmountMills: Int = 0
    @State private var totalCostCents: Int = 0
    @State private var fillUpType: FillUpType = .full
    @State private var notes = ""

    @FocusState private var focusedField: FuelingRecordFormView.EditableField?

    init(vehicle: Vehicle, onSave: ((FuelingRecord, Double) -> Void)? = nil) {
        self.vehicle = vehicle
        self.onSave = onSave
    }

    private var previousOdometer: Double {
        vehicle.lastRecord?.odometer ?? 0
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
                        Button("Done") { focusedField = nil }
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

        modelContext.insert(record)
        StatisticsCacheService.updateForNewRecord(record, vehicle: vehicle)
        onSave?(record, previousOdometer)
        dismiss()
    }
}

#Preview {
    AddRecordView(vehicle: Vehicle(name: "Test Car"))
        .modelContainer(for: [Vehicle.self, FuelingRecord.self], inMemory: true)
}
