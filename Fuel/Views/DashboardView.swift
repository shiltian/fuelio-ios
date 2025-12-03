import SwiftUI
import SwiftData

struct DashboardView: View {
    let vehicle: Vehicle

    private var records: [FuelingRecord] {
        vehicle.sortedRecords
    }

    private var statistics: VehicleStatistics {
        VehicleStatistics(records: records)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Quick Stats Cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatCard(
                        title: "Total Spent",
                        value: statistics.totalSpent.currencyFormatted,
                        icon: "dollarsign.circle.fill",
                        color: .orange
                    )

                    StatCard(
                        title: "Total Miles",
                        value: statistics.totalMiles.formatted(.number.precision(.fractionLength(0))),
                        icon: "road.lanes",
                        color: .blue
                    )

                    StatCard(
                        title: "Total Gallons",
                        value: statistics.totalGallons.formatted(.number.precision(.fractionLength(1))),
                        icon: "fuelpump.fill",
                        color: .green
                    )

                    StatCard(
                        title: "Avg MPG",
                        value: statistics.averageMPG.formatted(.number.precision(.fractionLength(1))),
                        icon: "gauge.with.dots.needle.67percent",
                        color: .purple
                    )

                    StatCard(
                        title: "Avg $/Mile",
                        value: statistics.averageCostPerMile.currencyFormatted,
                        icon: "chart.line.uptrend.xyaxis",
                        color: .red
                    )

                    StatCard(
                        title: "Avg Fill-up",
                        value: statistics.averageFillUpCost.currencyFormatted,
                        icon: "creditcard.fill",
                        color: .teal
                    )
                }
                .padding(.horizontal)

                // Last Fill-up Info
                if let lastRecord = records.first {
                    LastFillUpCard(record: lastRecord)
                        .padding(.horizontal)
                }

                // Charts Section
                if records.count >= 2 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Trends")
                            .font(.custom("Avenir Next", size: 20))
                            .fontWeight(.bold)
                            .padding(.horizontal)

                        ChartView(records: records)
                            .frame(height: 250)
                            .padding(.horizontal)
                    }
                }

                // Empty state
                if records.isEmpty {
                    EmptyRecordsView()
                        .padding(.top, 40)
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.custom("Avenir Next", size: 22))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(title)
                    .font(.custom("Avenir Next", size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

struct LastFillUpCard: View {
    let record: FuelingRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.teal)

                Text("Last Fill-up")
                    .font(.custom("Avenir Next", size: 16))
                    .fontWeight(.semibold)

                Spacer()

                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.custom("Avenir Next", size: 14))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(record.gallons.formatted(.number.precision(.fractionLength(2)))) gal")
                        .font(.custom("Avenir Next", size: 18))
                        .fontWeight(.semibold)
                    Text("Gallons")
                        .font(.custom("Avenir Next", size: 12))
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.totalCost.currencyFormatted)
                        .font(.custom("Avenir Next", size: 18))
                        .fontWeight(.semibold)
                    Text("Total")
                        .font(.custom("Avenir Next", size: 12))
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    if record.isInitialRecord {
                        Text("Baseline")
                            .font(.custom("Avenir Next", size: 18))
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        Text("First Record")
                            .font(.custom("Avenir Next", size: 12))
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(record.mpg.formatted(.number.precision(.fractionLength(1)))) MPG")
                            .font(.custom("Avenir Next", size: 18))
                            .fontWeight(.semibold)
                        Text("Efficiency")
                            .font(.custom("Avenir Next", size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            if record.isPartialFillUp {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                    Text("Partial fill-up")
                        .font(.custom("Avenir Next", size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

struct EmptyRecordsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "fuelpump")
                .font(.system(size: 50))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No fueling records yet")
                .font(.custom("Avenir Next", size: 18))
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Text("Tap + to add your first fill-up")
                .font(.custom("Avenir Next", size: 14))
                .foregroundColor(.secondary.opacity(0.8))
        }
    }
}

// MARK: - Statistics Calculator

struct VehicleStatistics {
    let records: [FuelingRecord]

    var totalSpent: Double {
        records.reduce(0) { $0 + $1.totalCost }
    }

    var totalMiles: Double {
        records.reduce(0) { $0 + $1.milesDriven }
    }

    var totalGallons: Double {
        records.reduce(0) { $0 + $1.gallons }
    }

    var averageMPG: Double {
        // Exclude partial fill-ups and initial records (baseline records have no valid MPG)
        let validRecords = records.filter { !$0.isPartialFillUp && !$0.isInitialRecord }
        guard !validRecords.isEmpty else { return 0 }

        let totalValidMiles = validRecords.reduce(0) { $0 + $1.milesDriven }
        let totalValidGallons = validRecords.reduce(0) { $0 + $1.gallons }
        guard totalValidGallons > 0 else { return 0 }
        return totalValidMiles / totalValidGallons
    }

    var averageCostPerMile: Double {
        guard totalMiles > 0 else { return 0 }
        return totalSpent / totalMiles
    }

    var averageFillUpCost: Double {
        guard !records.isEmpty else { return 0 }
        return totalSpent / Double(records.count)
    }

    var lastFillUpDate: Date? {
        records.first?.date
    }
}

// MARK: - Export/Import Views

struct ExportCSVView: View {
    let vehicle: Vehicle
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "doc.text")
                    .font(.system(size: 60))
                    .foregroundColor(.teal)

                Text("Export Fueling Data")
                    .font(.custom("Avenir Next", size: 24))
                    .fontWeight(.bold)

                Text("Export \(vehicle.sortedRecords.count) records as a CSV file")
                    .font(.custom("Avenir Next", size: 16))
                    .foregroundColor(.secondary)

                Button(action: exportData) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                        .font(.custom("Avenir Next", size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.teal, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
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
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }

    private func exportData() {
        let csvContent = CSVService.exportRecords(vehicle.sortedRecords, vehicleId: vehicle.id)

        let fileName = "\(vehicle.displayName.replacingOccurrences(of: " ", with: "_"))_fuel_records.csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
            exportURL = tempURL
            showingShareSheet = true
        } catch {
            print("Export error: \(error)")
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
                    .font(.custom("Avenir Next", size: 24))
                    .fontWeight(.bold)

                Text("Select a CSV file to import fueling records")
                    .font(.custom("Avenir Next", size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(action: { showingFilePicker = true }) {
                    Label("Choose File", systemImage: "folder")
                        .font(.custom("Avenir Next", size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.teal, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 40)

                if let error = errorMessage {
                    Text(error)
                        .font(.custom("Avenir Next", size: 14))
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
                let records = CSVService.importRecords(from: content)

                for record in records {
                    record.vehicle = vehicle
                    modelContext.insert(record)
                }

                importedCount = records.count
                showingSuccess = true
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

#Preview {
    NavigationStack {
        DashboardView(vehicle: Vehicle(name: "Test Car"))
    }
    .modelContainer(for: [Vehicle.self, FuelingRecord.self], inMemory: true)
}

