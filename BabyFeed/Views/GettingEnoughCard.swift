import SwiftUI

/// "Getting enough?" on Today, for the first six weeks: the last 24 hours of
/// wet and dirty diapers and feeds against what's usual at this age, and how
/// far along the way back to birth weight is.
///
/// A ✓ when a count meets what's usual, a plain number when it doesn't, never
/// red: a missed log is not a sick baby. The guidance's own red flags are the
/// only warnings, worded calmly, and the whole card opens the guidance with
/// its sources.
struct GettingEnoughCard: View {
    let summary: EnoughSummary
    let birthWeight: BirthWeightStatus
    let ageDays: Int
    let weightUnit: WeightUnit
    let now: Date

    @Environment(\.timeZone) private var timeZone
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Getting enough?")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("last 24 hours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) { stats }
                } else {
                    HStack(alignment: .top, spacing: 8) { stats }
                }
            }

            if ageDays < BirthWeightStatus.showsForDays, let line = birthWeight.line(weightUnit: weightUnit) {
                Label(EntryRow.wrappingAtDots(line), systemImage: "scalemass")
                    .font(.footnote)
                    .foregroundStyle(birthWeight.isRegained ? Color.primary : Color.secondary)
            }

            if case .notRegained = birthWeight {
                flag("Not back to birth weight by about two weeks. Worth a call to your pediatrician today.")
            }
            if let since = summary.noWetSince {
                let hours = Int(now.timeIntervalSince(since) / 3600)
                flag("No wet diaper logged since \(ClockText.since(since, now: now, in: timeZone)) (\(hours) h). If that's right, call your pediatrician.")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var stats: some View {
        stat(summary.wet, label: "wet", expectation: summary.wet.expected.map { range in
            range.lowerBound >= 5 ? "\(range.lowerBound)–\(range.upperBound)+ usual" : "\(range.lowerBound)–\(range.upperBound) usual"
        })
        stat(summary.dirty, label: "dirty", expectation: summary.dirty.expected.map { "\($0.lowerBound)–\($0.upperBound) usual" })
        stat(summary.feeds, label: summary.feeds.count == 1 ? "feed" : "feeds",
             expectation: summary.feeds.expected.map { "\($0.lowerBound)–\($0.upperBound) usual" })
    }

    private func stat(_ count: EnoughSummary.Count, label: String, expectation: String?) -> some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center, spacing: 2) {
            HStack(spacing: 4) {
                if count.meetsExpectation {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("As usual:")
                }
                Text("\(count.count) \(label)")
                    .font(.headline)
                    .monospacedDigit()
            }
            if let expectation {
                Text(expectation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
    }

    private func flag(_ text: String) -> some View {
        Label {
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "phone.fill")
                .foregroundStyle(.orange)
        }
    }
}
