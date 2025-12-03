import SwiftUI

struct FuelingSummaryPopup: View {
    let record: FuelingRecord

    @Environment(\.dismiss) private var dismiss

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
                // Initial record notice - shown instead of MPG for first record
                if record.isInitialRecord {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Baseline Recorded")
                                .font(.custom("Avenir Next", size: 18))
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)

                            Text("This is your first fill-up. MPG will be calculated from your next fill-up.")
                                .font(.custom("Avenir Next", size: 14))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "flag.checkered")
                            .font(.system(size: 44))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.blue.opacity(0.1))
                    )
                } else {
                    // MPG Card - Hero Stat (only shown for non-initial records)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Gas Mileage")
                                .font(.custom("Avenir Next", size: 14))
                                .foregroundColor(.secondary)

                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(record.mpg.formatted(.number.precision(.fractionLength(1))))
                                    .font(.custom("Avenir Next", size: 48))
                                    .fontWeight(.bold)
                                    .foregroundColor(.purple)

                                Text("MPG")
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

                    // Cost per Mile Card (only shown for non-initial records)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cost per Mile")
                                .font(.custom("Avenir Next", size: 14))
                                .foregroundColor(.secondary)

                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(record.costPerMile.currencyFormatted)
                                    .font(.custom("Avenir Next", size: 36))
                                    .fontWeight(.bold)
                                    .foregroundColor(.orange)

                                Text("/mile")
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
                    SummaryDetailCard(
                        title: "Miles Driven",
                        value: "\(record.milesDriven.formatted(.number.precision(.fractionLength(0)))) mi",
                        icon: "road.lanes",
                        color: .blue
                    )

                    SummaryDetailCard(
                        title: "Gallons",
                        value: "\(record.gallons.formatted(.number.precision(.fractionLength(2)))) gal",
                        icon: "fuelpump.fill",
                        color: .green
                    )

                    SummaryDetailCard(
                        title: "Price/Gallon",
                        value: record.pricePerGallon.currencyFormatted,
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
                        Text("Partial fill-up — MPG may be less accurate")
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
    FuelingSummaryPopup(
        record: FuelingRecord(
            currentMiles: 12500,
            previousMiles: 12200,
            pricePerGallon: 3.459,
            gallons: 10.5,
            totalCost: 36.32
        )
    )
}

