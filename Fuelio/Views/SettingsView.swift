import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cloudSyncService: CloudSyncService

    @Query private var vehicles: [Vehicle]
    @Query private var records: [FuelingRecord]

    @State private var showingDeleteAllAlert = false
    @State private var showingDeleteAllConfirmation = false
    @State private var showingDeleteSuccess = false

    // iCloud Sync state
    @State private var isSyncToggleOn = false
    @State private var showingConflictOptions = false
    @State private var showingToggleOffAlert = false
    @State private var showingICloudError = false
    @State private var iCloudErrorMessage = ""


    private var stateManager: SyncStateManager {
        cloudSyncService.stateManager
    }

    // App info
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    @ViewBuilder
    private var iCloudSyncSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { isSyncToggleOn },
                set: { newValue in
                    if newValue {
                        isSyncToggleOn = true
                        handleToggleOn()
                    } else {
                        showingToggleOffAlert = true
                    }
                }
            )) {
                HStack {
                    Image(systemName: "icloud.fill")
                        .foregroundColor(.blue)
                    Text("iCloud Sync")
                        .font(.custom("Avenir Next", size: 16))
                }
            }
            .disabled(stateManager.syncStatus.isInProgress)

            HStack {
                Text("Status")
                    .font(.custom("Avenir Next", size: 14))
                    .foregroundColor(.secondary)
                Spacer()
                if stateManager.syncStatus.isInProgress {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 4)
                }
                Text(stateManager.syncStatus.displayText)
                    .font(.custom("Avenir Next", size: 14))
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("iCloud")
                .font(.custom("Avenir Next", size: 12))
        } footer: {
            Text("Sync your fueling data across all your devices using iCloud.")
                .font(.custom("Avenir Next", size: 12))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                iCloudSyncSection

                // App Info Section
                Section {
                    InfoRow(label: "Version", value: appVersion)
                    InfoRow(label: "Build", value: buildNumber)
                } header: {
                    Text("App Information")
                        .font(.custom("Avenir Next", size: 12))
                }

                // Data Statistics Section
                Section {
                    InfoRow(label: "Vehicles", value: "\(vehicles.count)")
                    InfoRow(label: "Fueling Records", value: "\(records.count)")
                } header: {
                    Text("Local Data")
                        .font(.custom("Avenir Next", size: 12))
                }

                // iCloud Sync Details (only when sync is enabled)
                if stateManager.iCloudSyncEnabled {
                    Section {
                        NavigationLink {
                            iCloudSyncDetailView()
                        } label: {
                            HStack {
                                Image(systemName: "icloud.and.arrow.up.fill")
                                    .foregroundColor(.blue)
                                Text("iCloud Sync Details")
                                    .font(.custom("Avenir Next", size: 16))
                            }
                        }
                    }
                }

                // Danger Zone Section
                Section {
                    Button(role: .destructive) {
                        showingDeleteAllAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                                .foregroundColor(.red)
                            Text("Delete All Data")
                                .font(.custom("Avenir Next", size: 16))
                        }
                    }
                    .disabled(vehicles.isEmpty && records.isEmpty)
                } header: {
                    Text("Danger Zone")
                        .font(.custom("Avenir Next", size: 12))
                } footer: {
                    Text("This will permanently delete all vehicles and fueling records. This action cannot be undone.")
                        .font(.custom("Avenir Next", size: 12))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            // iCloud conflict resolution action sheet
            .confirmationDialog("iCloud Data Found", isPresented: $showingConflictOptions, titleVisibility: .visible) {
                Button("Use iCloud Data") {
                    performInitialSync(strategy: .overwriteLocal)
                }
                Button("Use Local Data") {
                    performInitialSync(strategy: .overwriteCloud)
                }
                Button("Merge Both") {
                    performInitialSync(strategy: .merge)
                }
                Button("Cancel", role: .cancel) {
                    isSyncToggleOn = false
                }
            } message: {
                Text("iCloud already contains fueling data. How would you like to handle this?")
            }
            // Toggle off alert
            .alert("Disable iCloud Sync?", isPresented: $showingToggleOffAlert) {
                Button("Keep Local Data") {
                    handleToggleOff(removeLocalData: false)
                }
                Button("Remove Local Data", role: .destructive) {
                    handleToggleOff(removeLocalData: true)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Do you want to keep or remove the local data on this device?")
            }
            // iCloud error
            .alert("iCloud Error", isPresented: $showingICloudError) {
                Button("OK") { }
            } message: {
                Text(iCloudErrorMessage)
            }
            // Delete all data alerts
            .alert("Delete All Data?", isPresented: $showingDeleteAllAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    showingDeleteAllConfirmation = true
                }
            } message: {
                Text("This will permanently delete \(vehicles.count) vehicle(s) and \(records.count) fueling record(s).")
            }
            .alert("Are You Sure?", isPresented: $showingDeleteAllConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Yes, Delete Everything", role: .destructive) {
                    deleteAllData()
                }
            } message: {
                Text("This action cannot be undone. All your data will be permanently deleted.")
            }
            .alert("Data Deleted", isPresented: $showingDeleteSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("All data has been successfully deleted.")
            }
            .onAppear {
                isSyncToggleOn = stateManager.iCloudSyncEnabled
            }
        }
    }

    // MARK: - iCloud Sync Handlers

    private func handleToggleOn() {
        Task {
            // Check iCloud availability
            let available = await cloudSyncService.checkiCloudAvailability()
            guard available else {
                isSyncToggleOn = false
                iCloudErrorMessage = "Please sign in to iCloud in Settings to use this feature."
                showingICloudError = true
                return
            }

            // Check if cloud has data
            let cloudHasData = await cloudSyncService.checkCloudHasData()

            if cloudHasData {
                // Show conflict resolution
                showingConflictOptions = true
            } else {
                // No cloud data: upload local and start syncing
                performInitialSync(strategy: .uploadLocal)
            }
        }
    }

    private enum InitialSyncStrategy {
        case uploadLocal      // No cloud data -- upload everything
        case overwriteLocal   // User chose "Use iCloud Data"
        case overwriteCloud   // User chose "Use Local Data"
        case merge            // User chose "Merge Both"
    }

    private func performInitialSync(strategy: InitialSyncStrategy) {
        Task {
            do {
                stateManager.iCloudSyncEnabled = true

                switch strategy {
                case .uploadLocal:
                    try await cloudSyncService.uploadAllLocalData(from: modelContext)

                case .overwriteLocal:
                    try await cloudSyncService.downloadAllCloudData(to: modelContext)

                case .overwriteCloud:
                    try await cloudSyncService.deleteAllCloudData()
                    try await cloudSyncService.uploadAllLocalData(from: modelContext)

                case .merge:
                    try await cloudSyncService.mergeCloudAndLocal(context: modelContext)
                }

                stateManager.markInitialSyncComplete()

                // Subscribe to remote changes and start monitoring local saves
                await cloudSyncService.subscribeToRemoteChanges()
                cloudSyncService.startMonitoring(container: modelContext.container)
            } catch {
                stateManager.iCloudSyncEnabled = false
                isSyncToggleOn = false
                iCloudErrorMessage = "Sync failed: \(error.localizedDescription)"
                showingICloudError = true
            }
        }
    }

    private func handleToggleOff(removeLocalData: Bool) {
        if removeLocalData {
            deleteAllData()
        }

        stateManager.iCloudSyncEnabled = false
        isSyncToggleOn = false
        stateManager.resetSyncState()
        cloudSyncService.stopMonitoring()
    }

    private func deleteAllData() {
        for record in records {
            modelContext.delete(record)
        }

        for vehicle in vehicles {
            modelContext.delete(vehicle)
        }

        do {
            try modelContext.save()
            showingDeleteSuccess = true
        } catch {
            print("Failed to delete all data: \(error)")
        }
    }
}

// MARK: - iCloud Sync Detail View

struct iCloudSyncDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var cloudSyncService: CloudSyncService

    @Query private var vehicles: [Vehicle]
    @Query private var records: [FuelingRecord]

    @State private var cloudVehicleCount: Int?
    @State private var cloudRecordCount: Int?
    @State private var isLoadingCloudCounts = false
    @State private var showingForceResyncAlert = false
    @State private var isResyncing = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        List {
            // Local counts for comparison
            Section {
                InfoRow(label: "Vehicles", value: "\(vehicles.count)")
                InfoRow(label: "Fueling Records", value: "\(records.count)")
            } header: {
                Text("Local Data")
                    .font(.custom("Avenir Next", size: 12))
            }

            // iCloud counts
            Section {
                cloudCountRow(label: "Vehicles", cloudCount: cloudVehicleCount, localCount: vehicles.count)
                cloudCountRow(label: "Fueling Records", cloudCount: cloudRecordCount, localCount: records.count)
            } header: {
                Text("iCloud Data")
                    .font(.custom("Avenir Next", size: 12))
            } footer: {
                if let vc = cloudVehicleCount, let rc = cloudRecordCount,
                   (vc != vehicles.count || rc != records.count) {
                    Text("Counts differ from local data. Use \"Force Re-sync from Local\" to wipe iCloud and re-upload all local data.")
                        .font(.custom("Avenir Next", size: 12))
                        .foregroundColor(.orange)
                }
            }

            // Actions
            Section {
                Button {
                    loadCloudCounts()
                } label: {
                    HStack {
                        Label("Refresh Counts", systemImage: "arrow.clockwise")
                            .font(.custom("Avenir Next", size: 16))
                        Spacer()
                        if isLoadingCloudCounts {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isLoadingCloudCounts || isResyncing)

                Button {
                    showingForceResyncAlert = true
                } label: {
                    HStack {
                        Label("Force Re-sync from Local", systemImage: "arrow.triangle.2.circlepath")
                            .font(.custom("Avenir Next", size: 16))
                        Spacer()
                        if isResyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isResyncing || isLoadingCloudCounts)
            } header: {
                Text("Actions")
                    .font(.custom("Avenir Next", size: 12))
            } footer: {
                Text("Force re-sync will delete all iCloud data and re-upload everything from this device.")
                    .font(.custom("Avenir Next", size: 12))
            }

            // Sync status
            Section {
                InfoRow(label: "Status", value: cloudSyncService.stateManager.syncStatus.displayText)
                InfoRow(label: "Sync Enabled", value: cloudSyncService.stateManager.iCloudSyncEnabled ? "Yes" : "No")
                InfoRow(label: "Initial Sync Done", value: cloudSyncService.stateManager.initialSyncCompleted ? "Yes" : "No")
            } header: {
                Text("Sync Status")
                    .font(.custom("Avenir Next", size: 12))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("iCloud Sync Details")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Force Re-sync?", isPresented: $showingForceResyncAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Re-sync", role: .destructive) {
                forceResyncFromLocal()
            }
        } message: {
            Text("This will delete all data in iCloud and re-upload all local data (\(vehicles.count) vehicle(s), \(records.count) record(s)). This may take a moment.")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadCloudCounts()
        }
    }

    @ViewBuilder
    private func cloudCountRow(label: String, cloudCount: Int?, localCount: Int) -> some View {
        HStack {
            Text(label)
                .font(.custom("Avenir Next", size: 16))
            Spacer()
            if isLoadingCloudCounts {
                ProgressView()
                    .scaleEffect(0.8)
            } else if let count = cloudCount {
                Text("\(count)")
                    .font(.custom("Avenir Next", size: 16))
                    .foregroundColor(count == localCount ? .secondary : .orange)
            } else {
                Text("--")
                    .font(.custom("Avenir Next", size: 16))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func loadCloudCounts() {
        isLoadingCloudCounts = true
        cloudVehicleCount = nil
        cloudRecordCount = nil
        Task {
            let counts = await cloudSyncService.fetchCloudRecordCounts()
            await MainActor.run {
                cloudVehicleCount = counts.vehicles
                cloudRecordCount = counts.fuelingRecords
                isLoadingCloudCounts = false
            }
        }
    }

    private func forceResyncFromLocal() {
        isResyncing = true
        cloudVehicleCount = nil
        cloudRecordCount = nil
        Task {
            do {
                try await cloudSyncService.deleteAllCloudData()
                try await cloudSyncService.uploadAllLocalData(from: modelContext)
                let counts = await cloudSyncService.fetchCloudRecordCounts()

                await MainActor.run {
                    cloudVehicleCount = counts.vehicles
                    cloudRecordCount = counts.fuelingRecords
                    isResyncing = false
                }
            } catch {
                await MainActor.run {
                    isResyncing = false
                    errorMessage = "Re-sync failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.custom("Avenir Next", size: 16))
            Spacer()
            Text(value)
                .font(.custom("Avenir Next", size: 16))
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Vehicle.self, FuelingRecord.self], inMemory: true)
        .environmentObject(CloudSyncService())
}
