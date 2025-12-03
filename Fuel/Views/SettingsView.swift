import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var vehicles: [Vehicle]
    @Query private var records: [FuelingRecord]

    @State private var showingDeleteAllAlert = false
    @State private var deleteConfirmationText = ""
    @State private var showingDeleteSuccess = false

    // App info
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    var body: some View {
        NavigationStack {
            List {
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
                    Text("Data Statistics")
                        .font(.custom("Avenir Next", size: 12))
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
            .alert("Delete All Data", isPresented: $showingDeleteAllAlert) {
                TextField("Type DELETE to confirm", text: $deleteConfirmationText)
                    .textInputAutocapitalization(.characters)
                Button("Cancel", role: .cancel) {
                    deleteConfirmationText = ""
                }
                Button("Delete Everything", role: .destructive) {
                    if deleteConfirmationText == "DELETE" {
                        deleteAllData()
                    }
                    deleteConfirmationText = ""
                }
                .disabled(deleteConfirmationText != "DELETE")
            } message: {
                Text("This will permanently delete \(vehicles.count) vehicle(s) and \(records.count) fueling record(s).\n\nType DELETE to confirm.")
            }
            .alert("Data Deleted", isPresented: $showingDeleteSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("All data has been successfully deleted.")
            }
        }
    }

    private func deleteAllData() {
        // Delete all records first
        for record in records {
            modelContext.delete(record)
        }

        // Delete all vehicles
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
}

