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

            HStack(alignment: .top) {
                stat(value: "\(summary.feedCount)", label: summary.feedCount == 1 ? "feed" : "feeds")
                Divider()
                stat(value: unit.format(milliliters: summary.totalML), label: "bottles")
                Divider()
                stat(value: "\(summary.nursingMinutes) min", label: "nursing")
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
