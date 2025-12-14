import SwiftUI
import SwiftData

struct AddVehicleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var make = ""
    @State private var model = ""
    @State private var yearString = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Vehicle Name", text: $name)
                        .font(.custom("Avenir Next", size: 16))
                } header: {
                    Text("Required")
                        .font(.custom("Avenir Next", size: 12))
                } footer: {
                    Text("Give your vehicle a nickname (e.g., \"My Tesla\", \"Family SUV\")")
                        .font(.custom("Avenir Next", size: 12))
                }

                Section {
                    TextField("Make (e.g., Toyota)", text: $make)
                        .font(.custom("Avenir Next", size: 16))

                    TextField("Model (e.g., Camry)", text: $model)
                        .font(.custom("Avenir Next", size: 16))

                    TextField("Year (e.g., 2023)", text: $yearString)
                        .font(.custom("Avenir Next", size: 16))
                        .keyboardType(.numberPad)
                } header: {
                    Text("Optional Details")
                        .font(.custom("Avenir Next", size: 12))
                }
            }
            .navigationTitle("Add Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveVehicle()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
    }

    private func saveVehicle() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMake = make.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        let vehicle = Vehicle(
            name: trimmedName,
            make: trimmedMake.isEmpty ? nil : trimmedMake,
            model: trimmedModel.isEmpty ? nil : trimmedModel,
            year: Int(yearString)
        )

        modelContext.insert(vehicle)
        dismiss()
    }
}

#Preview {
    AddVehicleView()
        .modelContainer(for: [Vehicle.self, FuelingRecord.self], inMemory: true)
}

