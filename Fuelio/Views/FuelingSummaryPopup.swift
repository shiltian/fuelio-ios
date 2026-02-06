import SwiftUI

struct FuelingSummaryPopup: View {
    let record: FuelingRecord
    let previousOdometer: Double
    let unitSystem: UnitSystem

    @Environment(\.dismiss) private var dismiss

    // Use cached values for performance
    private var efficiencyRaw: Double {
        record.getEfficiency()
    }

    private var efficiencyDisplay: Double {
        unitSystem.efficiencyDisplayValue(from: efficiencyRaw)
    }

    private var costPerDistanceValue: Double {
        record.getCostPerDistance()
    }

    private var distanceDrivenValue: Double {
        record.getDistanceDriven()
    }

    private var hasEfficiency: Bool {
        previousOdometer > 0 && !record.isPartialFillUp && efficiencyRaw > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.green.opacity(0.8), .mint.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }

                Text("Fill-up Recorded!")
                    .font(.custom("Avenir Next", size: 26))
                    .fontWeight(.bold)

                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.custom("Avenir Next", size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 32)

            // Stats Cards
            VStack(spacing: 16) {
                // Efficiency Card - Hero Stat (only show for full fill-ups with valid previous record)
                if hasEfficiency {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fuel Efficiency")
                                .font(.custom("Avenir Next", size: 14))
                                .foregroundColor(.secondary)

                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(efficiencyDisplay.formatted(.number.precision(.fractionLength(1))))
                                    .font(.custom("Avenir Next", size: 48))
                                    .fontWeight(.bold)
                                    .foregroundColor(.purple)

                                Text(unitSystem.efficiencyUnit)
                                    .font(.custom("Avenir Next", size: 18))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.purple.opacity(0.7))
                            }
                        }

                        Spacer()

                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 50))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .indigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.purple.opacity(0.1))
                    )

                    // Cost per Distance Card
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(unitSystem.costPerDistanceLabel)
                                .font(.custom("Avenir Next", size: 14))
                                .foregroundColor(.secondary)

                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(costPerDistanceValue.currencyFormatted)
                                    .font(.custom("Avenir Next", size: 36))
                                    .fontWeight(.bold)
                                    .foregroundColor(.orange)

                                Text(unitSystem.costPerDistanceShort)
                                    .font(.custom("Avenir Next", size: 16))
                                    .foregroundColor(.orange.opacity(0.7))
                            }
                        }

                        Spacer()

                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .yellow],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
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
                    if previousOdometer > 0 {
                        SummaryDetailCard(
                            title: "\(unitSystem.distanceName) Driven",
                            value: "\(distanceDrivenValue.formatted(.number.precision(.fractionLength(0)))) \(unitSystem.distanceUnit)",
                            icon: "road.lanes",
                            color: .blue
                        )
                    } else {
                        SummaryDetailCard(
                            title: "Odometer",
                            value: "\(record.odometer.formatted(.number.precision(.fractionLength(0)))) \(unitSystem.distanceUnit)",
                            icon: "speedometer",
                            color: .blue
                        )
                    }

                    SummaryDetailCard(
                        title: unitSystem.fuelName,
                        value: "\(record.fuelAmount.formatted(.number.precision(.fractionLength(2)))) \(unitSystem.fuelUnit)",
                        icon: "fuelpump.fill",
                        color: .green
                    )

                    SummaryDetailCard(
                        title: unitSystem.pricePerFuelLabel.replacingOccurrences(of: "Price per ", with: "Price/"),
                        value: record.pricePerFuelUnit.currencyFormatted,
                        icon: "tag.fill",
                        color: .teal
                    )

                    SummaryDetailCard(
                        title: "Total Cost",
                        value: record.totalCost.currencyFormatted,
                        icon: "creditcard.fill",
                        color: .pink
                    )
                }

                if record.isPartialFillUp {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Partial fill-up — efficiency may be less accurate")
                            .font(.custom("Avenir Next", size: 13))
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
                    .font(.custom("Avenir Next", size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.teal, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
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
                .font(.custom("Avenir Next", size: 17))
                .fontWeight(.semibold)

            Text(title)
                .font(.custom("Avenir Next", size: 12))
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
    FuelingSummaryPopup(
        record: FuelingRecord(
            odometer: 12500,
            pricePerFuelUnit: 3.459,
            fuelAmount: 10.5,
            totalCost: 36.32,
            vehicle: vehicle
        ),
        previousOdometer: 12200,
        unitSystem: .imperial
    )
}
