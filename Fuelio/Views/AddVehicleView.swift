import SwiftUI
import SwiftData

struct AddVehicleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var make = ""
    @State private var model = ""
    @State private var yearString = ""
    @State private var unitSystem: UnitSystem = .imperial

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Vehicle Name", text: $name)
                        .font(.appBody)
                } header: {
                    Text("Required")
                        .font(.appCaption)
                } footer: {
                    Text("Give your vehicle a nickname (e.g., \"My Tesla\", \"Family SUV\")")
                        .font(.appCaption)
                }

                Section {
                    TextField("Make (e.g., Toyota)", text: $make)
                        .font(.appBody)

                    TextField("Model (e.g., Camry)", text: $model)
                        .font(.appBody)

                    TextField("Year (e.g., 2023)", text: $yearString)
                        .font(.appBody)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Optional Details")
                        .font(.appCaption)
                }

                Section {
                    Picker("Unit System", selection: $unitSystem) {
                        ForEach(UnitSystem.allCases, id: \.self) { unit in
                            VStack(alignment: .leading) {
                                Text(unit.displayName)
                            }
                            .tag(unit)
                        }
                    }
                    .font(.appBody)
                    .pickerStyle(.menu)
                } header: {
                    Text("Units")
                        .font(.appCaption)
                } footer: {
                    Text(unitSystem.displayDescription)
                        .font(.appCaption)
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
            year: Int(yearString),
            unitSystem: unitSystem
        )

        modelContext.insert(vehicle)
        dismiss()
    }
}

#Preview {
    AddVehicleView()
        .modelContainer(for: [Vehicle.self, FuelingRecord.self], inMemory: true)
}
