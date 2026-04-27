import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os

// MARK: - CSV File Document

/// A simple `FileDocument` wrapper for CSV content, used with `.fileExporter`.
/// This bypasses the share sheet entirely, avoiding LaunchServices warnings.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(data: data, encoding: .utf8) ?? ""
        } else {
            content = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}

// MARK: - Export/Import Views

struct ExportCSVView: View {
    let vehicle: Vehicle
    @Environment(\.dismiss) private var dismiss
    @State private var csvDocument: CSVDocument?
    @State private var showingExporter = false
    @State private var showingSuccess = false

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.tianshilei.fuelio",
        category: "CSVExport"
    )

    private var defaultFileName: String {
        "\(vehicle.displayName.replacingOccurrences(of: " ", with: "_"))_fuel_records"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "doc.text")
                    .font(.system(size: 60))
                    .foregroundColor(.teal)

                Text("Export Fueling Data")
                    .font(.appTitle)
                    .fontWeight(.bold)

                Text("Export \(vehicle.fuelingRecords?.count ?? 0) records as a CSV file")
                    .font(.appBody)
                    .foregroundColor(.secondary)

                Button(action: {
                    let sorted = (vehicle.fuelingRecords ?? []).sorted { $0.date > $1.date }
                    csvDocument = CSVDocument(
                        content: CSVService.exportRecords(sorted)
                    )
                    showingExporter = true
                }) {
                    Label("Save to Files", systemImage: "folder")
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
            .fileExporter(
                isPresented: $showingExporter,
                document: csvDocument,
                contentType: .commaSeparatedText,
                defaultFilename: defaultFileName
            ) { result in
                switch result {
                case .success:
                    showingSuccess = true
                case .failure(let error):
                    Self.logger.error("Export error: \(error)")
                }
            }
            .alert("Export Successful", isPresented: $showingSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("CSV file saved successfully.")
            }
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

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.tianshilei.fuelio",
        category: "CSVImport"
    )

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
                errorMessage = String(localized: "Unable to access the selected file.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let records = CSVService.importRecords(from: content, vehicle: vehicle)

                let now = Date()
                for record in records {
                    record.modifiedAt = now
                    modelContext.insert(record)
                }
                try? modelContext.save()

                StatisticsCacheService.recalculateAllStatistics(for: vehicle)

                importedCount = records.count
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingSuccess = true
                }
            } catch {
                Self.logger.error("Failed to read CSV file: \(error)")
                errorMessage = String(localized: "Unable to read the selected file. Please make sure it is a valid CSV file.")
            }

        case .failure(let error):
            Self.logger.error("File picker failed: \(error)")
            errorMessage = String(localized: "Unable to open the selected file. Please try again.")
        }
    }
}

