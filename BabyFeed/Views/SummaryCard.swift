import SwiftUI

/// Three quick numbers for a window of time.
struct SummaryCard: View {
    let title: String
    let summary: FeedSummary
    let unit: VolumeUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Only the kinds that happened: a nursed-only day showed "0 oz
            // bottles", which reads as not eating rather than not measured.
            HStack(alignment: .top) {
                stat(value: "\(summary.feedCount)", label: summary.feedCount == 1 ? "feed" : "feeds")
                if summary.bottleCount > 0 || summary.nursingCount == 0 {
                    Divider()
                    stat(value: unit.format(milliliters: summary.totalML), label: "bottles")
                }
                if let nursing = summary.nursingText {
                    Divider()
                    stat(value: nursing, label: summary.nursingMinutes > 0 ? "nursing" : "no length logged")
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
