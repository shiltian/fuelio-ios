import SwiftUI
import SwiftData

struct CSVImportView: View {
    @Environment(\.dismiss) private var dismiss

    let fileURL: URL?
    let vehicles: [Vehicle]
    let onImport: ([FuelingRecord], Vehicle) -> Void

    @State private var csvContent: String = ""
    @State private var parsedRecords: [FuelingRecord] = []
    @State private var selectedVehicle: Vehicle?
    @State private var isLoading = true
    @State private var parseError: String?
    @State private var previewLines: [String] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("Loading CSV file...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = parseError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)

                        Text("Error Reading File")
                            .font(.custom("Avenir Next", size: 20))
                            .fontWeight(.semibold)

                        Text(error)
                            .font(.custom("Avenir Next", size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // File Info Section
                            fileInfoSection

                            // Preview Section
                            previewSection

                            // Vehicle Selection Section
                            if !vehicles.isEmpty {
                                vehicleSelectionSection
                            } else {
                                noVehicleWarning
                            }

                            // Import Summary
                            importSummarySection
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        if let vehicle = selectedVehicle {
                            onImport(parsedRecords, vehicle)
                            dismiss()
                        }
                    }
                    .disabled(selectedVehicle == nil || parsedRecords.isEmpty)
                }
            }
            .onAppear {
                loadAndParseCSV()
            }
            .onChange(of: selectedVehicle) { _, newValue in
                // Re-parse with the newly selected vehicle to ensure linkage
                reparseIfPossible(selectedVehicle: newValue)
            }
        }
    }

    // MARK: - View Components

    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("File Information", systemImage: "doc.text")
                .font(.custom("Avenir Next", size: 16))
                .fontWeight(.semibold)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileURL?.lastPathComponent ?? "Unknown file")
                        .font(.custom("Avenir Next", size: 14))
                        .fontWeight(.medium)

                    Text("\(parsedRecords.count) records found")
                        .font(.custom("Avenir Next", size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .opacity(parsedRecords.isEmpty ? 0 : 1)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Data Preview", systemImage: "eye")
                .font(.custom("Avenir Next", size: 16))
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(previewLines.prefix(6), id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    if previewLines.count > 6 {
                        Text("... and \(previewLines.count - 6) more rows")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding()
            }
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    private var vehicleSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Select Vehicle", systemImage: "car")
                .font(.custom("Avenir Next", size: 16))
                .fontWeight(.semibold)

            Text("Choose which vehicle to import the records to:")
                .font(.custom("Avenir Next", size: 12))
                .foregroundColor(.secondary)

            ForEach(vehicles) { vehicle in
                Button {
                    selectedVehicle = vehicle
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vehicle.name)
                                .font(.custom("Avenir Next", size: 14))
                                .fontWeight(.medium)

                            if let make = vehicle.make, let model = vehicle.model {
                                Text("\(make) \(model)")
                                    .font(.custom("Avenir Next", size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if selectedVehicle?.id == vehicle.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.teal)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedVehicle?.id == vehicle.id ? Color.teal.opacity(0.1) : Color(.systemGray6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selectedVehicle?.id == vehicle.id ? Color.teal : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var noVehicleWarning: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundColor(.orange)

            Text("No Vehicles Found")
                .font(.custom("Avenir Next", size: 16))
                .fontWeight(.semibold)

            Text("Please add a vehicle first before importing records.")
                .font(.custom("Avenir Next", size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    private var importSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Import Summary", systemImage: "list.bullet.clipboard")
                .font(.custom("Avenir Next", size: 16))
                .fontWeight(.semibold)

            if !parsedRecords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SummaryRow(label: "Total Records", value: "\(parsedRecords.count)")

                    if let firstDate = parsedRecords.map({ $0.date }).min(),
                       let lastDate = parsedRecords.map({ $0.date }).max() {
                        SummaryRow(label: "Date Range", value: "\(formatDate(firstDate)) - \(formatDate(lastDate))")
                    }

                    let totalGallons = parsedRecords.reduce(0) { $0 + $1.gallons }
                    SummaryRow(label: "Total Gallons", value: String(format: "%.2f", totalGallons))

                    let totalCost = parsedRecords.reduce(0) { $0 + $1.totalCost }
                    SummaryRow(label: "Total Cost", value: String(format: "$%.2f", totalCost))
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Helper Methods

    private func loadAndParseCSV() {
        guard let url = fileURL else {
            parseError = "No file URL provided"
            isLoading = false
            return
        }

        do {
            csvContent = try String(contentsOf: url, encoding: .utf8)

            // Validate the CSV
            let validation = CSVService.validateCSV(csvContent)
            if !validation.isValid {
                parseError = validation.error
                isLoading = false
                return
            }

            // Store preview lines
            previewLines = csvContent.components(separatedBy: .newlines).filter { !$0.isEmpty }

            // Auto-select the first vehicle if possible
            if selectedVehicle == nil {
                selectedVehicle = vehicles.first
            }

            reparseIfPossible(selectedVehicle: selectedVehicle)

            isLoading = false
        } catch {
            parseError = "Failed to read file: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func reparseIfPossible(selectedVehicle: Vehicle?) {
        guard let vehicle = selectedVehicle else { return }

        // Try parsing with the simple format first
        var records = CSVService.importSimpleFormat(from: csvContent, vehicle: vehicle)

        // If that didn't work, try the standard format
        if records.isEmpty {
            records = CSVService.importRecords(from: csvContent, vehicle: vehicle)
        }

        parsedRecords = records
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views

private struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.custom("Avenir Next", size: 14))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.custom("Avenir Next", size: 14))
                .fontWeight(.medium)
        }
    }
}

#Preview {
    CSVImportView(
        fileURL: nil,
        vehicles: [],
        onImport: { _, _ in }
    )
}

