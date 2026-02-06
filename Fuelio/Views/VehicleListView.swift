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
                        LinearGradient.brandSubdued
                    )
                    .frame(width: 50, height: 50)

                Image(systemName: "car.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(vehicle.displayName)
                    .font(.appHeadline)
                    .fontWeight(.semibold)

                if let lastRecord = vehicle.lastRecord {
                    Text("Last fill: \(lastRecord.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.appFootnote)
                        .foregroundColor(.secondary)
                } else {
                    Text("No records yet")
                        .font(.appFootnote)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if recordCount > 0 {
                Text("\(recordCount)")
                    .font(.appSubheadline)
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

    @State private var showingAddRecord = false
    @State private var showingSummary = false
    @State private var lastAddedRecord: FuelingRecord?
    @State private var lastAddedRecordPreviousOdometer: Double = 0
    @State private var showingVehicleSettings = false

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

                    Button(action: { showingVehicleSettings = true }) {
                        Label("Vehicle Settings", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddRecord = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(LinearGradient.brandDiagonal)
                }
            }
        }
        .sheet(isPresented: $showingAddRecord, onDismiss: {
            // Present the summary popup only AFTER the add-record sheet has fully
            // dismissed. Presenting two sheets simultaneously causes the second
            // sheet to appear empty or fail silently.
            if lastAddedRecord != nil {
                showingSummary = true
            }
        }) {
            AddRecordView(vehicle: vehicle) { record, prevOdometer in
                lastAddedRecord = record
                lastAddedRecordPreviousOdometer = prevOdometer
            }
        }
        .sheet(isPresented: $showingSummary) {
            if let record = lastAddedRecord {
                FuelingSummaryPopup(record: record, previousOdometer: lastAddedRecordPreviousOdometer, unitSystem: vehicle.unitSystem)
            }
        }
        .sheet(isPresented: $showingVehicleSettings) {
            VehicleSettingsView(vehicle: vehicle)
        }
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

