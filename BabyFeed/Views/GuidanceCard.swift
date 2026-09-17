import SwiftUI

/// "How much should I be feeding?" – target for the last 24 hours versus
/// what's been logged, from the AAP weight rule or age-typical ranges.
struct GuidanceCard: View {
    let target: FeedingGuidance.DailyTarget?
    let consumedML: Double
    let nursingMinutes: Int
    let unit: VolumeUnit
    let weightText: String?
    let babyName: String
    let onAddDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily target")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if let target {
                let fraction = min(consumedML / max(target.targetML, 1), 1.5)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(unit.format(milliliters: consumedML))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("of ~\(unit.format(milliliters: target.targetML)) in the last 24 h")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: min(fraction, 1))
                    .tint(fraction >= 1 ? .green : .accentColor)

                Text("About \(unit.format(milliliters: target.perFeedML)) per feed at \(target.feedsPerDay) feeds a day.")
                    .font(.subheadline)

                if let range = target.rangeML {
                    Text("Typical range \(unit.formatValue(unit.fromMilliliters(range.lowerBound)))–\(unit.format(milliliters: range.upperBound)) a day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if nursingMinutes > 0 {
                    Text("Plus \(nursingMinutes) min nursing, which isn't counted in the volume.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text(target.basis + (weightText.map { " Using \($0)." } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Add \(babyName)'s weight or birthday to see how much to feed.")
                    .font(.subheadline)
                Button(action: onAddDetails) {
                    Label("Add details", systemImage: "scalemass")
                }
                .buttonStyle(.bordered)
            }

            Text("Rules of thumb from the American Academy of Pediatrics. Every baby is different; your pediatrician's advice wins.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}
