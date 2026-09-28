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
            /// The same tally as numbers, for the table's columns.
            var wet = 0
            var dirty = 0

            var hasDiapers: Bool { wet > 0 || dirty > 0 }
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
        /// A food from the window, for the doctor's "what are they eating?".
        struct Food: Identifiable {
            let id: UUID
            let name: String
            let dateText: String
            let isFirstTime: Bool
            /// Only set when it isn't just "ate it" — refusals and reactions
            /// are the ones a doctor asks about.
            let reactionTitle: String?
            let flagged: Bool
        }

        /// Every day in the window with feeds or diapers logged, newest first.
        var days: [Day]
        var notes: [Note]
        var foods: [Food]
        /// How many days the feed averages divide by: the days with feeds.
        var feedDayCount = 0
        /// And the diaper averages: the days with diapers.
        var diaperDayCount = 0
        /// True when feeds and diapers were logged on exactly the same days,
        /// so one "averaged over" covers both.
        var feedsAndDiapersShareDays = false

        var hasFeeds: Bool { feedDayCount > 0 }
        var hasDiapers: Bool { diaperDayCount > 0 }
        var hasNotes: Bool { !notes.isEmpty }
        var hasFoods: Bool { !foods.isEmpty }

        /// What the per-day numbers were averaged over, said plainly, since a
        /// day nobody logged is left out rather than counted as a zero.
        var averagesFootnote: String? {
            func days(_ count: Int) -> String { count == 1 ? "the 1 day" : "the \(count) days" }
            switch (hasFeeds, hasDiapers) {
            case (true, true) where feedsAndDiapersShareDays:
                return "Averaged over \(days(feedDayCount)) with feeds and diapers logged."
            case (true, true):
                return "Feeds averaged over \(days(feedDayCount)) with feeds logged, diapers over \(days(diaperDayCount)) with diapers logged."
            case (true, false):
                return "Averaged over \(days(feedDayCount)) with feeds logged."
            case (false, true):
                return "Averaged over \(days(diaperDayCount)) with diapers logged."
            case (false, false):
                return nil
            }
        }
    }

    static func report(
        entries: [FeedEntry],
        weights: [WeightEntry],
        careNotes: [CareNote] = [],
        diapers: [DiaperEntry] = [],
        solidFoods: [SolidFoodEntry] = [],
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
        let diapersByDay = Dictionary(
            uniqueKeysWithValues: DayGrouping.group(recentDiapers, calendar: calendar) { $0.time }
                .map { ($0.day, DiaperTally($0.items)) }
        )

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
                value: latest.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: calendar.timeZone))
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

        }

        // Outside the feeds check: a stretch where only diapers got logged
        // still has diaper numbers worth showing.
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

        // A row for every day with feeds or diapers, so a day where only
        // diapers were logged isn't missing from the table.
        let feedsByDay = Dictionary(uniqueKeysWithValues: groups.map { ($0.day, $0.summary) })
        let allDays = Set(feedsByDay.keys).union(diapersByDay.keys).sorted(by: >)
        dayRows = allDays.map { day in
            let summary = feedsByDay[day] ?? FeedSummary()
            let tally = diapersByDay[day]
            return Report.Day(
                id: day,
                title: FeedStats.dayTitle(for: day, calendar: calendar, now: now),
                shortTitle: shortDayTitle(for: day, calendar: calendar, now: now),
                feedCount: summary.feedCount,
                volumeText: summary.bottleCount > 0 ? unit.format(milliliters: summary.totalML) : nil,
                nursingText: summary.nursingMinutes > 0 ? "\(summary.nursingMinutes) min" : nil,
                diaperText: (tally?.isEmpty ?? true) ? nil : tally?.text,
                wet: tally?.wet ?? 0,
                dirty: tally?.dirty ?? 0
            )
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

        // Foods in the window — first-times marked against the WHOLE log, not
        // just the window, so a food tried five weeks ago doesn't read as new.
        let foods = solidFoods
            .filter { $0.time >= cutoff && $0.deletedAt == nil }
            .sorted { $0.time > $1.time }
            .map { food in
                Report.Food(
                    id: food.uuid ?? UUID(),
                    name: food.name,
                    dateText: FeedStats.dayTitle(for: calendar.startOfDay(for: food.time), calendar: calendar, now: now),
                    isFirstTime: solidFoods.isFirstTime(food),
                    reactionTitle: food.reaction == .ate ? nil : food.reaction.title,
                    flagged: food.reaction == .possibleReaction
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
            notes: notes,
            foods: foods,
            feedDayCount: groups.count,
            diaperDayCount: diapersByDay.count,
            feedsAndDiapersShareDays: Set(feedsByDay.keys) == Set(diapersByDay.keys)
        )
    }

    /// "Today", "Yesterday", or "Tue 15" – narrow enough for a table column.
    private static func shortDayTitle(for day: Date, calendar: Calendar, now: Date) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day()
        style.timeZone = calendar.timeZone
        return day.formatted(style)
    }

    /// The shareable plain text, assembled from the same report the screen
    /// shows, and also what the on-device rewrite is given.
    static func factualSummary(
        entries: [FeedEntry],
        weights: [WeightEntry],
        careNotes: [CareNote] = [],
        diapers: [DiaperEntry] = [],
        solidFoods: [SolidFoodEntry] = [],
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
            solidFoods: solidFoods,
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
        }

        if !report.averageItems.isEmpty {
            lines.append("Per day — " + report.averageItems.map { "\($0.label.lowercased()) \($0.value)" }.joined(separator: ", "))
        }
        if !report.totalItems.isEmpty {
            lines.append("Totals — " + report.totalItems.map { "\($0.label.lowercased()) \($0.value)" }.joined(separator: ", "))
        }

        if !report.days.isEmpty {
            lines.append("")
            for day in report.days {
                lines.append("\(day.title): " + dayDetail(day))
            }
        }

        lines.append(contentsOf: foodLines(report))
        lines.append(contentsOf: noteLines(report))
        return lines.joined(separator: "\n")
    }

    /// "5 feeds · 16.9 oz · 17 min nursing · diapers 4 wet · 2 dirty". A day
    /// with only diapers logged says nothing about feeds rather than "0
    /// feeds": nobody logging a bottle isn't the baby not eating.
    static func dayDetail(_ day: Report.Day) -> String {
        var parts: [String] = []
        if day.feedCount > 0 {
            parts.append("\(day.feedCount) feed\(day.feedCount == 1 ? "" : "s")")
        }
        if let volume = day.volumeText { parts.append(volume) }
        if let nursing = day.nursingText { parts.append("\(nursing) nursing") }
        if let diapers = day.diaperText { parts.append("diapers \(diapers)") }
        return parts.joined(separator: " · ")
    }

    /// The foods, first-times and reactions marked, because "what's she eating
    /// now?" and "any reactions?" are questions asked at every visit from six
    /// months on.
    private static func foodLines(_ report: Report) -> [String] {
        guard report.hasFoods else { return [] }
        var lines = ["", "Foods"]
        for food in report.foods {
            var line = "\(food.dateText) — \(food.name)"
            if food.isFirstTime { line += " (first time)" }
            if let reaction = food.reactionTitle { line += ": \(reaction.lowercased())" }
            lines.append(line)
        }
        return lines
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
