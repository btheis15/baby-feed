import SwiftUI

/// Two weeks of patterns as plain numbers rather than charts: per-day averages
/// with the direction they moved, when feeds cluster, and a day-by-day list.
struct TrendsView: View {
    let groups: [DayGroup]
    let unit: VolumeUnit
    let targetML: Double?
    /// The user's calendar, so a pinned time zone reaches day boundaries and
    /// the hour-of-day breakdown, not just the clock face.
    var calendar: Calendar = .current
    var now: Date = .now

    /// Seven *complete* days ending yesterday, compared with the seven before
    /// that. Today is excluded from both so a half-finished day doesn't read as
    /// a drop.
    private var lastWeek: PeriodAverages { FeedStats.averages(groups, days: 7, skip: 1, calendar: calendar, now: now) }
    private var priorWeek: PeriodAverages { FeedStats.averages(groups, days: 7, skip: 8, calendar: calendar, now: now) }
    private var today: PeriodAverages { FeedStats.averages(groups, days: 1, calendar: calendar, now: now) }

    private var recentGroups: [DayGroup] { Array(groups.prefix(14)) }
    private var breakdown: DayPartBreakdown { DayPartBreakdown(recentGroups.flatMap(\.entries), calendar: calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            todayBlock
            weekBlock
            clusteringBlock
            dayByDayBlock
        }
    }

    // MARK: Today so far

    private var todayBlock: some View {
        block("Today so far") {
            statRow(
                "Volume",
                value: unit.format(milliliters: today.totalML),
                detail: targetProgressText
            )
            statRow("Feeds", value: "\(today.feedCount)")
            if today.nursingMinutes > 0 {
                statRow("Nursing", value: ElapsedText.compact(minutes: today.nursingMinutes))
            }
        }
    }

    private var targetProgressText: String? {
        guard let targetML, targetML > 0 else { return nil }
        let percent = Int((today.totalML / targetML * 100).rounded())
        return "\(percent)% of ~\(unit.format(milliliters: targetML))"
    }

    // MARK: Last 7 days

    private var weekBlock: some View {
        block("Last 7 days", subtitle: "Complete days, ending yesterday") {
            if lastWeek.isEmpty {
                Text("Nothing logged in the last week.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                statRow(
                    "Volume a day",
                    value: unit.format(milliliters: lastWeek.mlPerDay),
                    trend: trend(
                        lastWeek.mlPerDay,
                        priorWeek.isEmpty ? nil : priorWeek.mlPerDay,
                        format: { unit.format(milliliters: abs($0)) }
                    )
                )
                statRow(
                    "Feeds a day",
                    value: lastWeek.feedsPerDay.formatted(.number.precision(.fractionLength(0...1))),
                    trend: trend(
                        lastWeek.feedsPerDay,
                        priorWeek.isEmpty ? nil : priorWeek.feedsPerDay,
                        format: { abs($0).formatted(.number.precision(.fractionLength(0...1))) }
                    )
                )
                if let gap = FeedStats.averageGapHours(recentWeekEntries) {
                    statRow("Between feeds", value: FeedStats.durationText(hours: gap))
                }
                if let longest = FeedStats.longestGapHours(recentWeekEntries) {
                    statRow("Longest stretch", value: FeedStats.durationText(hours: longest))
                }
            }
        }
    }

    /// Entries from the same seven complete days the averages cover.
    private var recentWeekEntries: [FeedEntry] {
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: -1, to: today),
              let start = calendar.date(byAdding: .day, value: -7, to: today)
        else { return [] }
        return groups
            .filter { $0.day >= start && $0.day <= end }
            .flatMap(\.entries)
    }

    // MARK: When feeds happen

    private var clusteringBlock: some View {
        block("When feeds happen", subtitle: clusteringSubtitle) {
            ForEach(DayPart.allCases) { part in
                let count = breakdown.count(part)
                LabeledContent {
                    HStack(spacing: 8) {
                        Text("\(count)")
                            .monospacedDigit()
                        Text("\(Int((breakdown.share(part) * 100).rounded()))%")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(part.title)
                        Text(part.hoursText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var clusteringSubtitle: String {
        let total = breakdown.total
        let span = total == 1 ? "1 feed" : "\(total) feeds"
        guard let busiest = breakdown.busiest else {
            return "\(span) over the last \(recentGroups.count) days"
        }
        return "\(span) · mostly \(busiest.title.lowercased())"
    }

    // MARK: Day by day

    private var dayByDayBlock: some View {
        block("Day by day") {
            ForEach(recentGroups) { group in
                let summary = group.summary
                LabeledContent {
                    Text(summary.text(unit: unit))
                        .font(.subheadline)
                        .monospacedDigit()
                } label: {
                    Text(FeedStats.dayTitle(for: group.day, calendar: calendar, now: now))
                }
            }
        }
    }

    // MARK: Building blocks

    private func block<Content: View>(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
    }

    /// Laid out by hand rather than with `LabeledContent`: the trend line is a
    /// whole sentence, and putting it in a trailing accessory slot stretched
    /// the row to several hundred points.
    private func statRow(
        _ label: String,
        value: String,
        detail: String? = nil,
        trend: TrendChange? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                Spacer(minLength: 12)
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let trend {
                HStack(spacing: 4) {
                    Image(systemName: trend.symbol)
                        .imageScale(.small)
                    Text(trend.text)
                }
                .font(.caption)
                .foregroundStyle(trend.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Direction and size of a change against the previous period.
    private struct TrendChange {
        var text: String
        var symbol: String
        var tint: Color
    }

    /// Nil when there's no comparable previous period, or the change rounds to
    /// nothing worth pointing at.
    private func trend(
        _ current: Double,
        _ previous: Double?,
        format: (Double) -> String
    ) -> TrendChange? {
        guard let previous, previous > 0 else { return nil }
        let delta = current - previous
        // A sub-2% wobble is noise, not a trend.
        guard abs(delta) / previous >= 0.02 else {
            return TrendChange(text: "about the same", symbol: "equal", tint: .secondary)
        }
        return TrendChange(
            text: "\(format(delta)) vs. previous 7 days",
            symbol: delta > 0 ? "arrow.up" : "arrow.down",
            tint: delta > 0 ? .green : .orange
        )
    }
}
