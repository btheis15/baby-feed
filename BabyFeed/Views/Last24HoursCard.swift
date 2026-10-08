import SwiftUI

/// Today's short summary: what the last 24 hours add up to against the daily
/// target, with the diaper count. Tapping it opens the full cards.
///
/// The last 24 hours rather than the calendar day, like the target itself: at
/// 7 a.m. "today" has barely started, and a thin morning read against a whole
/// day's target looks like a problem that isn't there.
struct Last24HoursCard: View {
    let summary: FeedSummary
    let diapers: DiaperTally
    let target: FeedingGuidance.DailyTarget?
    let unit: VolumeUnit

    /// A volume bar only means something when there were bottles. A baby fed
    /// only at the breast would show "0 oz of ~25 oz", which reads as not
    /// eating rather than as not measured.
    private var showsVolume: Bool {
        target != nil && !(summary.nursingCount > 0 && summary.bottleCount == 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 24 hours")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if showsVolume, let target {
                let fraction = summary.totalML / max(target.targetML, 1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(unit.format(milliliters: summary.totalML))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text("of ~\(unit.format(milliliters: target.targetML)) target")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(fraction, 1))
                    .tint(fraction >= 1 ? .green : .accentColor)
                    .accessibilityHidden(true)
            }

            Text(EntryRow.wrappingAtDots(detailText))
                .font(.subheadline)

            if target == nil {
                Text("Add a weight or birthday to see a daily target.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// "6 feeds · 20 min nursing · 7 wet · 4 dirty", with the volume in it
    /// too when the bar above isn't already showing it.
    private var detailText: String {
        var parts = [summary.feedCount == 1 ? "1 feed" : "\(summary.feedCount) feeds"]
        if !showsVolume, summary.bottleCount > 0 {
            parts.append(unit.format(milliliters: summary.totalML))
        }
        if summary.nursingMinutes > 0 {
            parts.append("\(summary.nursingMinutes) min nursing")
        } else if summary.nursingCount > 0 {
            parts.append(summary.nursingCount == 1 ? "1 nursing" : "\(summary.nursingCount) nursing")
        }
        parts.append(diapers.isEmpty ? "no diapers" : diapers.text)
        return parts.joined(separator: " · ")
    }
}

/// Behind the card: the daily target in full, with where it came from, and
/// the day's numbers.
struct Last24HoursView: View {
    let summary: FeedSummary
    let diapers: DiaperTally
    let target: FeedingGuidance.DailyTarget?
    let projection: GrowthProjection?
    let unit: VolumeUnit
    let weightText: String?
    let weightUnit: WeightUnit
    let babyName: String

    @Environment(AppRouter.self) private var router

    var body: some View {
        List {
            Section {
                GuidanceCard(
                    target: target,
                    consumedML: summary.totalML,
                    nursingMinutes: summary.nursingMinutes,
                    nursingCount: summary.nursingCount,
                    unit: unit,
                    weightText: weightText,
                    babyName: babyName,
                    projection: projection,
                    weightUnit: weightUnit
                ) {
                    router.tab = .baby
                }
            }

            Section {
                SummaryCard(title: "Feeds", summary: summary, unit: unit)
            }

            Section("Diapers") {
                LabeledContent("Wet", value: "\(diapers.wet)")
                LabeledContent("Dirty", value: "\(diapers.dirty)")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Last 24 hours")
        .navigationBarTitleDisplayMode(.inline)
    }
}
