import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Builds the "for the pediatrician" summary. The factual version is plain
/// string assembly and always works; the friendly version asks the on-device
/// Apple Intelligence model to rewrite it, and is skipped when unavailable.
enum DaySummaryGenerator {
    static func factualSummary(
        entries: [FeedEntry],
        weights: [WeightEntry],
        days: Int,
        unit: VolumeUnit,
        weightUnit: WeightUnit,
        profile: BabyProfile,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> String {
        let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        let recent = entries.filter { $0.startTime >= cutoff }
        let groups = FeedStats.groupByDay(recent, calendar: calendar)
        let total = FeedSummary(recent)

        var lines: [String] = []
        var header = "\(profile.displayName)"
        if let age = profile.ageText(on: now, calendar: calendar) { header += ", \(age)" }
        header += " — feeding, last \(days) days"
        lines.append(header)

        if let latest = weights.first {
            var weightLine = "Latest weight: \(weightUnit.format(grams: latest.grams)) (\(latest.date.formatted(date: .abbreviated, time: .omitted)))"
            if weights.count >= 2 {
                let previous = weights[1]
                let weeks = latest.date.timeIntervalSince(previous.date) / (7 * 24 * 3600)
                if weeks > 0.2 {
                    weightLine += ", \(weightUnit.formatGain(gramsPerWeek: (latest.grams - previous.grams) / weeks))"
                }
            }
            lines.append(weightLine)
        }

        if groups.isEmpty {
            lines.append("No feeds logged in this period.")
            return lines.joined(separator: "\n")
        }

        let dayCount = Double(groups.count)
        let avgFeeds = Double(total.feedCount) / dayCount
        var average = "Average per day: \(avgFeeds.formatted(.number.precision(.fractionLength(1)))) feeds"
        if total.bottleCount > 0 {
            average += ", \(unit.format(milliliters: total.totalML / dayCount)) by bottle"
        }
        if total.nursingMinutes > 0 {
            average += ", \(Int((Double(total.nursingMinutes) / dayCount).rounded())) min nursing"
        }
        lines.append(average)

        if let gap = FeedStats.averageGapHours(recent) {
            lines.append("Typical gap between feeds: \(gap.formatted(.number.precision(.fractionLength(1)))) hours")
        }

        let formulaML = recent.filter { $0.kind == .formula }.reduce(0) { $0 + ($1.amountML ?? 0) }
        let breastMilkML = recent.filter { $0.kind == .breastMilk }.reduce(0) { $0 + ($1.amountML ?? 0) }
        if formulaML > 0 || breastMilkML > 0 {
            var mix: [String] = []
            if formulaML > 0 { mix.append("formula \(unit.format(milliliters: formulaML))") }
            if breastMilkML > 0 { mix.append("breast milk \(unit.format(milliliters: breastMilkML))") }
            if total.nursingCount > 0 { mix.append("\(total.nursingCount) nursing sessions") }
            lines.append("Totals: " + mix.joined(separator: ", "))
        }

        lines.append("")
        for group in groups {
            lines.append("\(FeedStats.dayTitle(for: group.day, calendar: calendar, now: now)): \(group.summary.text(unit: unit))")
        }
        return lines.joined(separator: "\n")
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
