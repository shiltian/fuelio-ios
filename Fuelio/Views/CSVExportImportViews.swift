import SwiftUI
import SwiftData
import os

// MARK: - Export/Import Views

struct ExportableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct ExportCSVView: View {
    let vehicle: Vehicle
    @Environment(\.dismiss) private var dismiss
    @State private var exportItem: ExportableURL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "doc.text")
                    .font(.system(size: 60))
                    .foregroundColor(.teal)

                Text("Export Fueling Data")
                    .font(.appTitle)
                    .fontWeight(.bold)

                Text("Export \(vehicle.sortedRecords.count) records as a CSV file")
                    .font(.appBody)
                    .foregroundColor(.secondary)

                Button(action: exportData) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                        .font(.appButton)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(LinearGradient.brandHorizontal)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 40)

                Spacer()
            }
            .padding(.top, 60)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $exportItem) { item in
                ShareSheet(activityItems: [item.url])
            }
        }
    }

    private func exportData() {
        let csvContent = CSVService.exportRecords(vehicle.sortedRecords)

        let fileName = "\(vehicle.displayName.replacingOccurrences(of: " ", with: "_"))_fuel_records.csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
            exportItem = ExportableURL(url: tempURL)
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "me.tianshilei.fuelio", category: "CSVExport")
                .error("Export error: \(error)")
        }
    }
}

struct ImportCSVView: View {
    let vehicle: Vehicle
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingFilePicker = false
    @State private var importedCount = 0
    @State private var showingSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 60))
                    .foregroundColor(.teal)

                Text("Import Fueling Data")
                    .font(.appTitle)
                    .fontWeight(.bold)

                Text("Select a CSV file to import fueling records")
                    .font(.appBody)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(action: { showingFilePicker = true }) {
                    Label("Choose File", systemImage: "folder")
                        .font(.appButton)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(LinearGradient.brandHorizontal)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 40)

                if let error = errorMessage {
                    Text(error)
                        .font(.appSubheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                }

                Spacer()
            }
            .padding(.top, 60)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .alert("Import Successful", isPresented: $showingSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Successfully imported \(importedCount) records.")
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Unable to access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let records = CSVService.importRecords(from: content, vehicle: vehicle)

                for record in records {
                    modelContext.insert(record)
                }

                StatisticsCacheService.recalculateAllStatistics(for: vehicle)

                importedCount = records.count
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingSuccess = true
                }
            } catch {
                errorMessage = "Failed to read file: \(error.localizedDescription)"
            }

        case .failure(let error):
            errorMessage = "Failed to select file: \(error.localizedDescription)"
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
