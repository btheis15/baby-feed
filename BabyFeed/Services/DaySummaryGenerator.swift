import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Builds the "for the pediatrician" summary. The factual version is plain
/// string assembly and always works; the friendly version asks the on-device
/// Apple Intelligence model to rewrite it, and is skipped when unavailable.
enum DaySummaryGenerator {
    /// The summary as data, so the screen can lay it out as a table and the
    /// shared text can be assembled from the same numbers. Building both from
    /// one report is the point – they can't drift apart.
    struct Report {
        /// One row of the day-by-day table.
        struct Day: Identifiable {
            let id: Date
            /// "Today", "Yesterday", "Tue, Sep 15" – for the shared text.
            let title: String
            /// "Today", "Yesterday", "Tue 15" – short enough for a column.
            let shortTitle: String
            let feedCount: Int
            /// Nil when the day had no bottles.
            let volumeText: String?
            /// Nil when the day had no nursing.
            let nursingText: String?
            /// "4 wet · 2 dirty" — nil when no diapers were logged that day.
            let diaperText: String?
        }

        /// One label/value pair, which is all most of this report is.
        struct Item: Identifiable {
            let id: String
            let label: String
            let value: String
        }

        /// A note logged in the window – the thing you'd otherwise forget.
        struct Note: Identifiable {
            let id: UUID
            let dateText: String
            let kindTitle: String
            /// "Moderate", when the kind has a severity.
            let severityTitle: String?
            /// Who wrote it, when a name was set. Empty otherwise.
            let author: String
            let text: String
        }

        var babyName: String
        var ageText: String?
        var windowText: String
        /// Latest weight, its date, and the rate if there's a previous one.
        var weightItems: [Item]
        /// Per-day averages.
        var averageItems: [Item]
        /// Totals across the window.
        var totalItems: [Item]
        var days: [Day]
        var notes: [Note]

        var hasFeeds: Bool { !days.isEmpty }
        var hasNotes: Bool { !notes.isEmpty }
    }

    static func report(
        entries: [FeedEntry],
        weights: [WeightEntry],
        careNotes: [CareNote] = [],
        diapers: [DiaperEntry] = [],
        days: Int,
        unit: VolumeUnit,
        weightUnit: WeightUnit,
        profile: BabyProfile,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Report {
        let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        let recent = entries.filter { $0.startTime >= cutoff }
        let groups = FeedStats.groupByDay(recent, calendar: calendar)
        let total = FeedSummary(recent)

        // Diapers, tallied per calendar day. Wet count per day is the question
        // a pediatrician actually asks, so it belongs in this report.
        let recentDiapers = diapers.filter { $0.time >= cutoff && $0.deletedAt == nil }
        let diapersByDay = Dictionary(grouping: recentDiapers) { calendar.startOfDay(for: $0.time) }
            .mapValues(DiaperTally.init)

        var weightItems: [Report.Item] = []
        if let latest = weights.first {
            weightItems.append(.init(
                id: "latest",
                label: "Latest weight",
                value: weightUnit.format(grams: latest.grams)
            ))
            weightItems.append(.init(
                id: "weighed",
                label: "Weighed",
                value: latest.date.formatted(date: .abbreviated, time: .omitted)
            ))
            if let rate = WeightStats.overallGramsPerWeek(weights) {
                weightItems.append(.init(
                    id: "rate",
                    label: "Gain",
                    value: weightUnit.formatGain(gramsPerWeek: rate)
                ))
            }
        }

        var averageItems: [Report.Item] = []
        var totalItems: [Report.Item] = []
        var dayRows: [Report.Day] = []

        if !groups.isEmpty {
            let dayCount = Double(groups.count)
            averageItems.append(.init(
                id: "feeds",
                label: "Feeds",
                value: (Double(total.feedCount) / dayCount).formatted(.number.precision(.fractionLength(1)))
            ))
            if total.bottleCount > 0 {
                averageItems.append(.init(
                    id: "bottle",
                    label: "By bottle",
                    value: unit.format(milliliters: total.totalML / dayCount)
                ))
            }
            if total.nursingMinutes > 0 {
                averageItems.append(.init(
                    id: "nursing",
                    label: "Nursing",
                    value: "\(Int((Double(total.nursingMinutes) / dayCount).rounded())) min"
                ))
            }
            if let gap = FeedStats.averageGapHours(recent) {
                averageItems.append(.init(
                    id: "gap",
                    label: "Typical gap",
                    value: FeedStats.durationText(hours: gap)
                ))
            }
            if !diapersByDay.isEmpty {
                // Averaged over days with diapers logged, same reasoning as
                // feeds: a day nobody logged shouldn't read as a dry day.
                let diaperDayCount = Double(diapersByDay.count)
                let totalWet = diapersByDay.values.reduce(0) { $0 + $1.wet }
                let totalDirty = diapersByDay.values.reduce(0) { $0 + $1.dirty }
                if totalWet > 0 {
                    averageItems.append(.init(
                        id: "wetDiapers",
                        label: "Wet diapers",
                        value: (Double(totalWet) / diaperDayCount).formatted(.number.precision(.fractionLength(1)))
                    ))
                }
                if totalDirty > 0 {
                    averageItems.append(.init(
                        id: "dirtyDiapers",
                        label: "Dirty diapers",
                        value: (Double(totalDirty) / diaperDayCount).formatted(.number.precision(.fractionLength(1)))
                    ))
                }
            }

            let formulaML = recent.filter { $0.kind == .formula }.reduce(0) { $0 + ($1.amountML ?? 0) }
            let breastMilkML = recent.filter { $0.kind == .breastMilk }.reduce(0) { $0 + ($1.amountML ?? 0) }
            if formulaML > 0 {
                totalItems.append(.init(id: "formula", label: "Formula", value: unit.format(milliliters: formulaML)))
            }
            if breastMilkML > 0 {
                totalItems.append(.init(id: "breastMilk", label: "Breast milk", value: unit.format(milliliters: breastMilkML)))
            }
            if total.nursingCount > 0 {
                totalItems.append(.init(
                    id: "sessions",
                    label: "Nursing sessions",
                    value: "\(total.nursingCount)"
                ))
            }

            dayRows = groups.map { group in
                let summary = group.summary
                let tally = diapersByDay[group.day]
                return Report.Day(
                    id: group.day,
                    title: FeedStats.dayTitle(for: group.day, calendar: calendar, now: now),
                    shortTitle: shortDayTitle(for: group.day, calendar: calendar, now: now),
                    feedCount: summary.feedCount,
                    volumeText: summary.bottleCount > 0 ? unit.format(milliliters: summary.totalML) : nil,
                    nursingText: summary.nursingMinutes > 0 ? "\(summary.nursingMinutes) min" : nil,
                    diaperText: (tally?.isEmpty ?? true) ? nil : tally?.text
                )
            }
        }

        let notes = careNotes
            .filter { $0.date >= cutoff && $0.deletedAt == nil }
            .sorted { $0.date > $1.date }
            .map { careNote in
                Report.Note(
                    id: careNote.uuid ?? UUID(),
                    dateText: FeedStats.dayTitle(for: calendar.startOfDay(for: careNote.date), calendar: calendar, now: now),
                    kindTitle: careNote.kind.title,
                    severityTitle: careNote.severity?.title,
                    author: careNote.loggedByName,
                    text: careNote.note
                )
            }

        return Report(
            babyName: profile.displayName,
            ageText: profile.ageText(on: now, calendar: calendar),
            windowText: "Last \(days) days",
            weightItems: weightItems,
            averageItems: averageItems,
            totalItems: totalItems,
            days: dayRows,
            notes: notes
        )
    }

    /// "Today", "Yesterday", or "Tue 15" – narrow enough for a table column.
    private static func shortDayTitle(for day: Date, calendar: Calendar, now: Date) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.weekday(.abbreviated).day())
    }

    /// The shareable plain text, assembled from the same report the screen
    /// shows, and also what the on-device rewrite is given.
    static func factualSummary(
        entries: [FeedEntry],
        weights: [WeightEntry],
        careNotes: [CareNote] = [],
        diapers: [DiaperEntry] = [],
        days: Int,
        unit: VolumeUnit,
        weightUnit: WeightUnit,
        profile: BabyProfile,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> String {
        plainText(from: report(
            entries: entries,
            weights: weights,
            careNotes: careNotes,
            diapers: diapers,
            days: days,
            unit: unit,
            weightUnit: weightUnit,
            profile: profile,
            calendar: calendar,
            now: now
        ))
    }

    static func plainText(from report: Report) -> String {
        var lines: [String] = []

        var header = report.babyName
        if let age = report.ageText { header += ", \(age)" }
        header += " — feeding, \(report.windowText.lowercased())"
        lines.append(header)

        if !report.weightItems.isEmpty {
            lines.append(report.weightItems.map { "\($0.label): \($0.value)" }.joined(separator: ", "))
        }

        if !report.hasFeeds {
            lines.append("No feeds logged in this period.")
            lines.append(contentsOf: noteLines(report))
            return lines.joined(separator: "\n")
        }

        if !report.averageItems.isEmpty {
            lines.append("Per day — " + report.averageItems.map { "\($0.label.lowercased()) \($0.value)" }.joined(separator: ", "))
        }
        if !report.totalItems.isEmpty {
            lines.append("Totals — " + report.totalItems.map { "\($0.label.lowercased()) \($0.value)" }.joined(separator: ", "))
        }

        lines.append("")
        for day in report.days {
            var parts = ["\(day.feedCount) feed\(day.feedCount == 1 ? "" : "s")"]
            if let volume = day.volumeText { parts.append(volume) }
            if let nursing = day.nursingText { parts.append("\(nursing) nursing") }
            if let diapers = day.diaperText { parts.append("diapers \(diapers)") }
            lines.append("\(day.title): " + parts.joined(separator: " · "))
        }

        lines.append(contentsOf: noteLines(report))
        return lines.joined(separator: "\n")
    }

    /// Pulled out so a window with no feeds still carries its notes – the
    /// point of them is the appointment, and they mustn't depend on whether
    /// anyone remembered to log bottles that week.
    private static func noteLines(_ report: Report) -> [String] {
        guard report.hasNotes else { return [] }
        var lines = ["", "Notes"]
        for note in report.notes {
            var heading = "\(note.dateText) — \(note.kindTitle)"
            if let severity = note.severityTitle { heading += " (\(severity.lowercased()))" }
            if !note.author.isEmpty { heading += ", logged by \(note.author)" }
            lines.append("\(heading): \(note.text)")
        }
        return lines
    }

    /// True when Apple Intelligence is available on this device.
    static var canRewrite: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    /// On-device rewrite into a few friendly sentences. Nil when unavailable or on error.
    static func friendlySummary(from facts: String) async -> String? {
        #if canImport(FoundationModels)
        guard canRewrite else { return nil }
        let session = LanguageModelSession(instructions: """
            You help a tired parent share a newborn feeding summary with their pediatrician. \
            Rewrite the facts below as three to five short, plain sentences. \
            Keep every number exactly as given. Do not add medical advice or invent anything.
            """)
        do {
            return try await session.respond(to: facts).content
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
