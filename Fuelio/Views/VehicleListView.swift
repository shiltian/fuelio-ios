import SwiftUI
import SwiftData

struct VehicleListView: View {
    let vehicles: [Vehicle]
    @Binding var selectedVehicle: Vehicle?
    @Binding var showingAddVehicle: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var showingDeleteAlert = false
    @State private var vehicleToDelete: Vehicle?
    @State private var showingSettings = false

    var body: some View {
        List {
            ForEach(vehicles) { vehicle in
                NavigationLink(value: vehicle) {
                    VehicleRowView(vehicle: vehicle)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        vehicleToDelete = vehicle
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("My Vehicles")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddVehicle = true }) {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert("Delete Vehicle", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                vehicleToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let vehicle = vehicleToDelete {
                    deleteVehicle(vehicle)
                }
            }
        } message: {
            Text("Are you sure you want to delete this vehicle and all its fueling records? This action cannot be undone.")
        }
    }

    private func deleteVehicle(_ vehicle: Vehicle) {
        withAnimation {
            modelContext.delete(vehicle)
            vehicleToDelete = nil
        }
    }
}

struct VehicleRowView: View {
    let vehicle: Vehicle

    // Use cached record count for performance
    private var recordCount: Int {
        vehicle.cachedRecordCount ?? vehicle.fuelingRecords?.count ?? 0
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.teal.opacity(0.7), .cyan.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Image(systemName: "car.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(vehicle.displayName)
                    .font(.custom("Avenir Next", size: 17))
                    .fontWeight(.semibold)

                if let lastRecord = vehicle.lastRecord {
                    Text("Last fill: \(lastRecord.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.custom("Avenir Next", size: 13))
                        .foregroundColor(.secondary)
                } else {
                    Text("No records yet")
                        .font(.custom("Avenir Next", size: 13))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if recordCount > 0 {
                Text("\(recordCount)")
                    .font(.custom("Avenir Next", size: 14))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 8)
    }
}

struct VehicleDetailView: View {
    let vehicle: Vehicle

    @Environment(\.modelContext) private var modelContext
    @State private var showingAddRecord = false
    @State private var showingExportOptions = false
    @State private var showingImportPicker = false
    @State private var showingSummary = false
    @State private var lastAddedRecord: FuelingRecord?
    @State private var lastAddedRecordPreviousOdometer: Double = 0
    @State private var showingClearHistoryAlert = false
    @State private var showingClearHistoryConfirmation = false
    @State private var showingClearHistorySuccess = false
    @State private var showingUnitConversion = false

    private var recordCount: Int {
        vehicle.fuelingRecords?.count ?? 0
    }

    var body: some View {
        TabView {
            DashboardView(vehicle: vehicle)
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent")
                }

            HistoryView(vehicle: vehicle)
                .tabItem {
                    Label("History", systemImage: "list.bullet.rectangle")
                }
        }
        .navigationTitle(vehicle.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingAddRecord = true }) {
                        Label("Add Fueling", systemImage: "plus")
                    }

                    Divider()

                    Button(action: { showingUnitConversion = true }) {
                        Label("Unit System (\(vehicle.unitSystem.displayName))", systemImage: "ruler")
                    }

                    Divider()

                    Button(action: { showingExportOptions = true }) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(vehicle.fuelingRecords?.isEmpty ?? true)

                    Button(action: { showingImportPicker = true }) {
                        Label("Import CSV", systemImage: "square.and.arrow.down")
                    }

                    Divider()

                    Button(role: .destructive, action: { showingClearHistoryAlert = true }) {
                        Label("Clear Fueling History", systemImage: "trash")
                    }
                    .disabled(vehicle.fuelingRecords?.isEmpty ?? true)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddRecord = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.teal, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
        }
        .sheet(isPresented: $showingAddRecord) {
            AddRecordView(vehicle: vehicle) { record, prevOdometer in
                lastAddedRecord = record
                lastAddedRecordPreviousOdometer = prevOdometer
                showingSummary = true
            }
        }
        .sheet(isPresented: $showingSummary) {
            if let record = lastAddedRecord {
                FuelingSummaryPopup(record: record, previousOdometer: lastAddedRecordPreviousOdometer, unitSystem: vehicle.unitSystem)
            }
        }
        .sheet(isPresented: $showingExportOptions) {
            ExportCSVView(vehicle: vehicle)
        }
        .sheet(isPresented: $showingImportPicker) {
            ImportCSVView(vehicle: vehicle)
        }
        .sheet(isPresented: $showingUnitConversion) {
            UnitConversionView(vehicle: vehicle)
        }
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
    }

    private func clearFuelingHistory() {
        guard let records = vehicle.fuelingRecords else { return }

        for record in records {
            modelContext.delete(record)
        }

        // Invalidate cache after clearing
        vehicle.invalidateCache()
        vehicle.cachedRecordCount = 0
        vehicle.cacheLastUpdated = Date()

        showingClearHistorySuccess = true
    }
}

// MARK: - Unit Conversion View

struct UnitConversionView: View {
    let vehicle: Vehicle

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedUnit: UnitSystem
    @State private var showingConfirmation = false

    init(vehicle: Vehicle) {
        self.vehicle = vehicle
        _selectedUnit = State(initialValue: vehicle.unitSystem)
    }

    private var recordCount: Int {
        vehicle.fuelingRecords?.count ?? 0
    }

    private var hasChanged: Bool {
        selectedUnit != vehicle.unitSystem
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(UnitSystem.allCases, id: \.self) { unit in
                        Button {
                            selectedUnit = unit
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(unit.displayName)
                                        .font(.custom("Avenir Next", size: 16))
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    Text(unit.displayDescription)
                                        .font(.custom("Avenir Next", size: 13))
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
                        .font(.custom("Avenir Next", size: 12))
                } footer: {
                    if hasChanged && recordCount > 0 {
                        Text("Changing the unit system will convert all \(recordCount) existing record(s) to \(selectedUnit.displayName). This cannot be undone.")
                            .font(.custom("Avenir Next", size: 12))
                            .foregroundColor(.orange)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Unit System")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if hasChanged && recordCount > 0 {
                            showingConfirmation = true
                        } else if hasChanged {
                            applyUnitChange()
                        } else {
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanged)
                }
            }
            .alert("Convert Records?", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Convert", role: .destructive) {
                    applyUnitChange()
                }
            } message: {
                Text("Convert all \(recordCount) record(s) from \(vehicle.unitSystem.displayName) to \(selectedUnit.displayName)? This cannot be undone.")
            }
        }
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

        do {
            try modelContext.save()
        } catch {
            print("Failed to save unit conversion: \(error)")
        }

        dismiss()
    }
}

#Preview {
    NavigationStack {
        VehicleListView(
            vehicles: [],
            selectedVehicle: .constant(nil),
            showingAddVehicle: .constant(false)
        )
    }
        .modelContainer(for: [Vehicle.self, FuelingRecord.self], inMemory: true)
}
