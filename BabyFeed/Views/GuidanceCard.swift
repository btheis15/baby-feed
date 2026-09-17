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
    /// Set when the target came from a percentile projection rather than a
    /// weight measured today, so the card can say where the number came from.
    var projection: GrowthProjection?
    var weightUnit: WeightUnit = .poundsOunces
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

                Text(basisText(for: target))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let provenance {
                    Text(provenance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if projection?.isStale == true {
                    Label(
                        "It's been a while since \(babyName) was weighed – a fresh weight will sharpen this.",
                        systemImage: "scalemass"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
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

    /// The basis sentence with the weight it was derived from appended.
    /// `basis` only sometimes ends in a period – the weight-based one reads
    /// "…at 7.5 lb" – so close it off before starting the next sentence.
    ///
    /// When the weight is projected the provenance moves to its own line
    /// instead, so "Using 7 lb 8 oz" can't be mistaken for a measurement.
    private func basisText(for target: FeedingGuidance.DailyTarget) -> String {
        let sentence = target.basis.hasSuffix(".") ? target.basis : target.basis + "."
        guard let weightText, projection == nil || projection?.isMeasured == true else { return sentence }
        return "\(sentence) Using \(weightText)."
    }

    /// Where a projected number came from. Nil when the weight was measured,
    /// because then the basis line already says it.
    private var provenance: String? {
        guard let projection, !projection.isMeasured else { return nil }
        let centile = GrowthProjector.ordinal(percentile: projection.anchorPercentile)
        let weighed = projection.anchorDate.formatted(date: .abbreviated, time: .omitted)
        let anchor = weightUnit.format(grams: projection.anchorGrams)
        return "Estimated for today from the \(centile) percentile · last weighed \(anchor) on \(weighed)."
    }
}
