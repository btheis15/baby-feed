import AppIntents
import Foundation
import SwiftData

/// Feed kinds as Siri and Shortcuts see them.
enum FeedKindAppEnum: String, AppEnum {
    case formula
    case breastMilk
    case nursing

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Feed Kind" }

    static var caseDisplayRepresentations: [FeedKindAppEnum: DisplayRepresentation] {
        [
            .formula: "Formula",
            .breastMilk: "Breast milk",
            .nursing: "Nursing",
        ]
    }

    var kind: FeedKind { FeedKind(rawValue: rawValue) ?? .formula }
}

/// "Hey Siri, log a feed in Baby Feed." Runs in the background; no UI needed.
struct LogFeedIntent: AppIntent {
    static var title: LocalizedStringResource { "Log a Feed" }
    static var description: IntentDescription { IntentDescription("Logs a bottle or nursing session in Baby Feed.") }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Kind", default: .formula)
    var kind: FeedKindAppEnum

    @Parameter(title: "Amount (in your units)")
    var amount: Double?

    @Parameter(title: "Minutes (nursing)")
    var minutes: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$kind) feed")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(AppModelContainer.shared)
        let unit = AppSettings.volumeUnit
        let feedKind = kind.kind

        let entry: FeedEntry
        if feedKind.usesVolume {
            let ml = amount.map { unit.toMilliliters($0) } ?? FeedDefaults.defaultAmountML(for: feedKind, unit: unit)
            entry = FeedEntry(kind: feedKind, amountML: ml)
            FeedDefaults.setDefaultAmountML(ml, for: feedKind)
        } else {
            let duration = minutes ?? FeedDefaults.defaultNursingMinutes()
            entry = FeedEntry(kind: feedKind, durationMinutes: duration)
            FeedDefaults.setDefaultNursingMinutes(duration)
        }

        context.insert(entry)
        FeedCoordinator.feedsDidChange(in: context)

        let text = "Logged \(feedKind.title.lowercased()), \(entry.detailText(unit: unit))."
        return .result(dialog: "\(text)")
    }
}

/// "Hey Siri, when did the baby last eat in Baby Feed?"
struct LastFeedIntent: AppIntent {
    static var title: LocalizedStringResource { "When Was the Last Feed?" }
    static var description: IntentDescription { IntentDescription("Tells you how long since the last feed and when the next is due.") }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(AppModelContainer.shared)
        var fetch = FetchDescriptor<FeedEntry>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
        fetch.fetchLimit = 1

        guard let last = try context.fetch(fetch).first else {
            return .result(dialog: "No feeds logged yet.")
        }

        let unit = AppSettings.volumeUnit
        let elapsed = FeedStats.elapsedText(since: last.startTime)
        let when = elapsed == "Just now" ? "just now" : "\(elapsed) ago"
        var text = "Last feed was \(when): \(last.kind.title.lowercased()), \(last.detailText(unit: unit))."
        if AppSettings.remindersEnabled {
            let due = AppSettings.nextDue(after: last.startTime)
            text += due > .now
                ? " Next feed is due around \(due.formatted(date: .omitted, time: .shortened))."
                : " The next feed is due now."
        }
        return .result(dialog: "\(text)")
    }
}

/// Phrases Siri recognises without any setup.
struct BabyFeedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFeedIntent(),
            phrases: [
                "Log a feed in \(.applicationName)",
                "Log a bottle in \(.applicationName)",
                "\(.applicationName) log feed",
            ],
            shortTitle: "Log a Feed",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: LastFeedIntent(),
            phrases: [
                "When did the baby last eat in \(.applicationName)",
                "Last feed in \(.applicationName)",
                "\(.applicationName) last feed",
            ],
            shortTitle: "Last Feed",
            systemImageName: "clock.fill"
        )
    }
}
