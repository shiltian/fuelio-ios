import SwiftUI
import SwiftData
import os

struct VehicleSettingsView: View {
    let vehicle: Vehicle

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Vehicle detail editing
    @State private var name: String
    @State private var make: String
    @State private var model: String
    @State private var yearString: String

    // Unit system
    @State private var selectedUnit: UnitSystem
    @State private var showingUnitConversionAlert = false

    // CSV
    @State private var showingExportOptions = false
    @State private var showingImportPicker = false

    // Clear history
    @State private var showingClearHistoryAlert = false
    @State private var showingClearHistoryConfirmation = false
    @State private var showingClearHistorySuccess = false

    init(vehicle: Vehicle) {
        self.vehicle = vehicle
        _name = State(initialValue: vehicle.name)
        _make = State(initialValue: vehicle.make ?? "")
        _model = State(initialValue: vehicle.model ?? "")
        _yearString = State(initialValue: vehicle.year != nil ? "\(vehicle.year!)" : "")
        _selectedUnit = State(initialValue: vehicle.unitSystem)
    }

    private var recordCount: Int {
        vehicle.displayRecordCount
    }

    private var unitHasChanged: Bool {
        selectedUnit != vehicle.unitSystem
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Vehicle Details
                Section {
                    TextField("Vehicle Name", text: $name)
                        .font(.appBody)

                    TextField("Make (e.g., Toyota)", text: $make)
                        .font(.appBody)

                    TextField("Model (e.g., Camry)", text: $model)
                        .font(.appBody)

                    TextField("Year (e.g., 2023)", text: $yearString)
                        .font(.appBody)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Vehicle Details")
                        .font(.appCaption)
                }

                // MARK: - Unit System
                Section {
                    ForEach(UnitSystem.allCases, id: \.self) { unit in
                        Button {
                            selectedUnit = unit
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(unit.displayName)
                                        .font(.appBody)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    Text(unit.displayDescription)
                                        .font(.appFootnote)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if selectedUnit == unit {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.teal)
                                        .font(.title2)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Unit System")
                        .font(.appCaption)
                } footer: {
                    if unitHasChanged && recordCount > 0 {
                        Text("Changing the unit system will convert all \(recordCount) existing record(s) to \(selectedUnit.displayName). This cannot be undone.")
                            .font(.appCaption)
                            .foregroundColor(.orange)
                    }
                }

                // MARK: - Data
                Section {
                    Button {
                        showingExportOptions = true
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                            .font(.appBody)
                    }
                    .disabled(vehicle.fuelingRecords?.isEmpty ?? true)

                    Button {
                        showingImportPicker = true
                    } label: {
                        Label("Import CSV", systemImage: "square.and.arrow.down")
                            .font(.appBody)
                    }
                } header: {
                    Text("Data")
                        .font(.appCaption)
                }

                // MARK: - Danger Zone
                Section {
                    Button(role: .destructive) {
                        showingClearHistoryAlert = true
                    } label: {
                        Label("Clear Fueling History", systemImage: "trash")
                            .font(.appBody)
                    }
                    .disabled(vehicle.fuelingRecords?.isEmpty ?? true)
                } header: {
                    Text("Danger Zone")
                        .font(.appCaption)
                } footer: {
                    if recordCount > 0 {
                        Text("This will permanently delete all \(recordCount) fueling record(s). The vehicle itself will be kept.")
                            .font(.appCaption)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Vehicle Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if unitHasChanged && recordCount > 0 {
                            showingUnitConversionAlert = true
                        } else {
                            saveAndDismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            // Unit conversion confirmation
            .alert("Convert Records?", isPresented: $showingUnitConversionAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Convert & Save", role: .destructive) {
                    saveAndDismiss()
                }
            } message: {
                Text("This will convert all \(recordCount) record(s) from \(vehicle.unitSystem.displayName) to \(selectedUnit.displayName). This cannot be undone.")
            }
            // Clear history alerts
            .alert("Clear Fueling History?", isPresented: $showingClearHistoryAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    showingClearHistoryConfirmation = true
                }
            } message: {
                Text("This will delete all \(recordCount) fueling record(s) for this vehicle. The vehicle itself will be kept.")
            }
            .alert("Are You Sure?", isPresented: $showingClearHistoryConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Yes, Delete All Records", role: .destructive) {
                    clearFuelingHistory()
                }
            } message: {
                Text("This action cannot be undone. All fueling history for this vehicle will be permanently deleted.")
            }
            .alert("History Cleared", isPresented: $showingClearHistorySuccess) {
                Button("OK") { }
            } message: {
                Text("All fueling records have been deleted.")
            }
            // CSV sheets
            .sheet(isPresented: $showingExportOptions) {
                ExportCSVView(vehicle: vehicle)
            }
            .sheet(isPresented: $showingImportPicker) {
                ImportCSVView(vehicle: vehicle)
            }
        }
    }

    // MARK: - Actions

    private func saveAndDismiss() {
        // Save vehicle detail edits
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMake = make.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        vehicle.name = trimmedName
        vehicle.make = trimmedMake.isEmpty ? nil : trimmedMake
        vehicle.model = trimmedModel.isEmpty ? nil : trimmedModel
        vehicle.year = Int(yearString)
        vehicle.modifiedAt = Date()

        // Apply unit conversion if changed
        if unitHasChanged {
            applyUnitChange()
        }

        do {
            try modelContext.save()
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "me.tianshilei.fuelio", category: "VehicleSettings")
                .error("Failed to save vehicle settings: \(error)")
        }

        dismiss()
    }

    private func applyUnitChange() {
        let oldUnit = vehicle.unitSystem
        let newUnit = selectedUnit

        // Convert all existing records
        if let records = vehicle.fuelingRecords {
            for record in records {
                record.odometer = newUnit.convertDistance(from: oldUnit, value: record.odometer)
                record.fuelAmount = newUnit.convertFuel(from: oldUnit, value: record.fuelAmount)
                record.pricePerFuelUnit = newUnit.convertPricePerFuel(from: oldUnit, value: record.pricePerFuelUnit)
                // totalCost stays the same
            }
        }

        // Update vehicle's unit system
        vehicle.unitSystem = newUnit

        // Rebuild cache with converted values
        StatisticsCacheService.recalculateAllStatistics(for: vehicle)
    }

    private func clearFuelingHistory() {
        guard let records = vehicle.fuelingRecords else { return }

        do {
            for record in records {
                modelContext.delete(record)
            }
            try modelContext.save()

            // Invalidate cache after clearing
            vehicle.invalidateCache()
            vehicle.cachedRecordCount = 0
            vehicle.cacheLastUpdated = Date()
            try modelContext.save()

            showingClearHistorySuccess = true
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "me.tianshilei.fuelio", category: "VehicleSettings")
                .error("Failed to clear fueling history: \(error)")
        }
    }
}

#Preview {
    VehicleSettingsView(vehicle: Vehicle(name: "Test Car"))
        .modelContainer(for: [Vehicle.self, FuelingRecord.self], inMemory: true)
}
