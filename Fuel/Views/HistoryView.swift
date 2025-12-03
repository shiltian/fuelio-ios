import SwiftUI
import SwiftData

struct HistoryView: View {
    let vehicle: Vehicle

    @Environment(\.modelContext) private var modelContext
    @State private var recordToEdit: FuelingRecord?
    @State private var showingDeleteAlert = false
    @State private var recordToDelete: FuelingRecord?
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .dateDescending

    enum SortOrder: String, CaseIterable {
        case dateDescending = "Newest First"
        case dateAscending = "Oldest First"
        case costHighest = "Highest Cost"
        case costLowest = "Lowest Cost"
        case mpgHighest = "Best MPG"
        case mpgLowest = "Worst MPG"
    }

    private var records: [FuelingRecord] {
        vehicle.sortedRecords
    }

    private var filteredRecords: [FuelingRecord] {
        var result = records

        if !searchText.isEmpty {
            result = result.filter { record in
                record.notes?.localizedCaseInsensitiveContains(searchText) ?? false ||
                record.date.formatted(date: .abbreviated, time: .omitted).localizedCaseInsensitiveContains(searchText) ||
                record.totalCost.currencyFormatted.localizedCaseInsensitiveContains(searchText)
            }
        }

        switch sortOrder {
        case .dateDescending:
            result.sort { $0.date > $1.date }
        case .dateAscending:
            result.sort { $0.date < $1.date }
        case .costHighest:
            result.sort { $0.totalCost > $1.totalCost }
        case .costLowest:
            result.sort { $0.totalCost < $1.totalCost }
        case .mpgHighest:
            // Initial records have no valid MPG, sort them to the end
            result.sort { r1, r2 in
                if r1.isInitialRecord && !r2.isInitialRecord { return false }
                if !r1.isInitialRecord && r2.isInitialRecord { return true }
                return r1.mpg > r2.mpg
            }
        case .mpgLowest:
            // Initial records have no valid MPG, sort them to the end
            result.sort { r1, r2 in
                if r1.isInitialRecord && !r2.isInitialRecord { return false }
                if !r1.isInitialRecord && r2.isInitialRecord { return true }
                return r1.mpg < r2.mpg
            }
        }

        return result
    }

    var body: some View {
        Group {
            if records.isEmpty {
                EmptyHistoryView()
            } else {
                List {
                    // Sort picker section
                    Section {
                        Picker("Sort By", selection: $sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue)
                                    .tag(order)
                            }
                        }
                        .font(.custom("Avenir Next", size: 14))
                    }

                    // Records section
                    Section {
                        ForEach(filteredRecords) { record in
                            FuelingRecordRow(record: record)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    recordToEdit = record
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        recordToDelete = record
                                        showingDeleteAlert = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button {
                                        recordToEdit = record
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                    } header: {
                        Text("\(filteredRecords.count) records")
                            .font(.custom("Avenir Next", size: 12))
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Search records")
            }
        }
        .sheet(item: $recordToEdit) { record in
            EditRecordView(record: record)
        }
        .alert("Delete Record", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                recordToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let record = recordToDelete {
                    deleteRecord(record)
                }
            }
        } message: {
            Text("Are you sure you want to delete this fueling record? This action cannot be undone.")
        }
    }

    private func deleteRecord(_ record: FuelingRecord) {
        withAnimation {
            modelContext.delete(record)
            recordToDelete = nil
        }
    }
}

struct FuelingRecordRow: View {
    let record: FuelingRecord

    var body: some View {
        VStack(spacing: 12) {
            // Header with date and cost
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.custom("Avenir Next", size: 16))
                        .fontWeight(.semibold)

                    Text(record.date.formatted(date: .omitted, time: .shortened))
                        .font(.custom("Avenir Next", size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(record.totalCost.currencyFormatted)
                    .font(.custom("Avenir Next", size: 20))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }

            // Details row
            HStack(spacing: 16) {
                DetailChip(
                    icon: "fuelpump.fill",
                    value: "\(record.gallons.formatted(.number.precision(.fractionLength(2)))) gal",
                    color: .green
                )

                DetailChip(
                    icon: "dollarsign",
                    value: "\(record.pricePerGallon.formatted(.number.precision(.fractionLength(3))))/gal",
                    color: .orange
                )

                if record.isInitialRecord {
                    DetailChip(
                        icon: "flag.checkered",
                        value: "Baseline",
                        color: .blue
                    )
                } else {
                    DetailChip(
                        icon: "gauge",
                        value: "\(record.mpg.formatted(.number.precision(.fractionLength(1)))) MPG",
                        color: .purple
                    )
                }

                Spacer()
            }

            // Odometer info
            HStack {
                Image(systemName: "speedometer")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\(record.previousMiles.formatted(.number.precision(.fractionLength(0)))) → \(record.currentMiles.formatted(.number.precision(.fractionLength(0)))) mi")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.secondary)

                Text("(\(record.milesDriven.formatted(.number.precision(.fractionLength(0)))) miles)")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.secondary.opacity(0.8))

                Spacer()

                if record.isPartialFillUp {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("Partial")
                            .font(.custom("Avenir Next", size: 11))
                    }
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.yellow.opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            // Notes if present
            if let notes = record.notes, !notes.isEmpty {
                HStack {
                    Image(systemName: "note.text")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(notes)
                        .font(.custom("Avenir Next", size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    Spacer()
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct DetailChip: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)

            Text(value)
                .font(.custom("Avenir Next", size: 12))
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Fueling History")
                .font(.custom("Avenir Next", size: 20))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text("Your fueling records will appear here")
                .font(.custom("Avenir Next", size: 14))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    NavigationStack {
        HistoryView(vehicle: Vehicle(name: "Test Car"))
    }
    .modelContainer(for: [Vehicle.self, FuelingRecord.self], inMemory: true)
}

