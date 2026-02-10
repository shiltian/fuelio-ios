import SwiftUI

// MARK: - Value-type snapshot of a fueling record for the summary popup.
// Using a plain struct instead of the SwiftData model object avoids any
// issues with model faulting / context invalidation during sheet transitions.
struct FuelingSummaryData: Identifiable {
    let id = UUID()
    let date: Date
    let odometer: Double
    let fuelAmount: Double
    let pricePerFuelUnit: Double
    let totalCost: Double
    let isPartialFillUp: Bool
    let previousOdometer: Double
    let efficiencyRaw: Double
    let costPerDistance: Double
    let distanceDriven: Double
    let unitSystem: UnitSystem

    /// Create a snapshot from a FuelingRecord at save time, capturing all
    /// computed values while the model object is guaranteed to be valid.
    init(record: FuelingRecord, previousOdometer: Double, unitSystem: UnitSystem) {
        self.date = record.date
        self.odometer = record.odometer
        self.fuelAmount = record.fuelAmount
        self.pricePerFuelUnit = record.pricePerFuelUnit
        self.totalCost = record.totalCost
        self.isPartialFillUp = record.isPartialFillUp
        self.previousOdometer = previousOdometer
        self.efficiencyRaw = record.getEfficiency()
        self.costPerDistance = record.getCostPerDistance()
        self.distanceDriven = record.getDistanceDriven()
        self.unitSystem = unitSystem
    }

    var efficiencyDisplay: Double {
        unitSystem.efficiencyDisplayValue(from: efficiencyRaw)
    }

    var hasEfficiency: Bool {
        previousOdometer > 0 && !isPartialFillUp && efficiencyRaw > 0
    }
}

struct FuelingSummaryPopup: View {
    let data: FuelingSummaryData

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.success)
                        .frame(width: 80, height: 80)

                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }

                Text("Fill-up Recorded!")
                    .font(.appLargeTitle)
                    .fontWeight(.bold)

                Text(data.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.appSubheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 32)

            // Stats Cards
            VStack(spacing: 16) {
                // Efficiency Card - Hero Stat (only show for full fill-ups with valid previous record)
                if data.hasEfficiency {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fuel Efficiency")
                                .font(.appSubheadline)
                                .foregroundColor(.secondary)

                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(data.efficiencyDisplay.formatted(.number.precision(.fractionLength(1))))
                                    .font(.appHero)
                                    .fontWeight(.bold)
                                    .foregroundColor(.purple)

                                Text(data.unitSystem.efficiencyUnit)
                                    .font(.appButton)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.purple.opacity(0.7))
                            }
                        }

                        Spacer()

                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 50))
                            .foregroundStyle(LinearGradient.efficiencyIcon)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.purple.opacity(0.1))
                    )

                    // Cost per Distance Card
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(data.unitSystem.costPerDistanceLabel)
                                .font(.appSubheadline)
                                .foregroundColor(.secondary)

                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(data.costPerDistance.currencyFormatted)
                                    .font(.appHero2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.orange)

                                Text(data.unitSystem.costPerDistanceShort)
                                    .font(.appBody)
                                    .foregroundColor(.orange.opacity(0.7))
                            }
                        }

                        Spacer()

                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(LinearGradient.costIcon)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.orange.opacity(0.1))
                    )
                }

                // Details Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    if data.previousOdometer > 0 {
                        SummaryDetailCard(
                            title: "\(data.unitSystem.distanceName) Driven",
                            value: "\(data.distanceDriven.formatted(.number.precision(.fractionLength(0)))) \(data.unitSystem.distanceUnit)",
                            icon: "road.lanes",
                            color: .blue
                        )
                    } else {
                        SummaryDetailCard(
                            title: "Odometer",
                            value: "\(data.odometer.formatted(.number.precision(.fractionLength(0)))) \(data.unitSystem.distanceUnit)",
                            icon: "speedometer",
                            color: .blue
                        )
                    }

                    SummaryDetailCard(
                        title: data.unitSystem.fuelName,
                        value: "\(data.fuelAmount.formatted(.number.precision(.fractionLength(2)))) \(data.unitSystem.fuelUnit)",
                        icon: "fuelpump.fill",
                        color: .green
                    )

                    SummaryDetailCard(
                        title: data.unitSystem.pricePerFuelLabel.replacingOccurrences(of: "Price per ", with: "Price/"),
                        value: data.pricePerFuelUnit.currencyFormatted,
                        icon: "tag.fill",
                        color: .teal
                    )

                    SummaryDetailCard(
                        title: "Total Cost",
                        value: data.totalCost.currencyFormatted,
                        icon: "creditcard.fill",
                        color: .pink
                    )
                }

                if data.isPartialFillUp {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Partial fill-up — efficiency may be less accurate")
                            .font(.appFootnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.yellow.opacity(0.1))
                    )
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Done Button
            Button(action: { dismiss() }) {
                Text("Done")
                    .font(.appButton)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                    LinearGradient.brandHorizontal
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct SummaryDetailCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.appHeadline)
                .fontWeight(.semibold)

            Text(title)
                .font(.appCaption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    let vehicle = Vehicle(name: "Test Car")
    let record = FuelingRecord(
        odometer: 12500,
        pricePerFuelUnit: 3.459,
        fuelAmount: 10.5,
        totalCost: 36.32,
        vehicle: vehicle
    )
    record.cachedPreviousOdometer = 12200
    record.cachedDistanceDriven = 300
    record.cachedEfficiency = 300.0 / 10.5
    record.cachedCostPerDistance = 36.32 / 300.0
    return FuelingSummaryPopup(
        data: FuelingSummaryData(record: record, previousOdometer: 12200, unitSystem: .imperial)
    )
}
