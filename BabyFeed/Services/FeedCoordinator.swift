import Foundation
import SwiftData
import WidgetKit

/// The one place that reacts to data changing. Every save or delete funnels
/// through here so widgets, the reminder, the Live Activity and sync stay in step.
@MainActor
enum FeedCoordinator {
    /// How many of the newest feeds this needs, across all babies on the phone.
    ///
    /// Everything below reads the very recent end of the log: the last feed,
    /// the last 24 hours, and the median of the last ten bottles of each kind.
    /// Fetching the whole log instead — which this did — materialises every
    /// feed ever logged, on the main actor, between tapping Save and the sheet
    /// closing, and again on every foreground and after every sync. 400 covers
    /// well over a fortnight of newborn feeding even with twins.
    private static let recentFeedLimit = 400
    /// The target only reads the latest weigh-in, and the projection anchors on
    /// it. Two would do; this leaves room for soft-deleted rows.
    private static let recentWeightLimit = 40

    static func feedsDidChange(in context: ModelContext, triggerSync: Bool = true) {
        try? context.save()

        let babyID = AppSettings.currentBabyID
        let entries = fetchRecent(FeedEntry.self, sortedBy: \.startTime, limit: recentFeedLimit, in: context)
            .active(for: babyID)
        let weights = fetchRecent(WeightEntry.self, sortedBy: \.date, limit: recentWeightLimit, in: context)
            .active(for: babyID)

        let unit = AppSettings.volumeUnit
        let profile = BabyProfile.load()
        let lastFeed = entries.first
        let due = lastFeed.map { AppSettings.nextDue(after: $0.startTime) }

        let recent = FeedStats.entries(entries, within: 24 * 60 * 60)
        let summary = FeedSummary(recent)
        // The same shared call the screens use, so the widget can't show a
        // target the app disagrees with.
        let target = FeedingGuidance.currentTarget(
            weights: weights,
            profile: profile,
            style: AppSettings.feedingStyle,
            feedsPerDay: AppSettings.feedsPerDay,
            calendar: AppSettings.calendar
        ).target

        // Mirrored out so the log sheet, quick-log buttons and Siri can all
        // start a bottle at the right amount without touching SwiftData.
        FeedDefaults.recommendedPerFeedML = target?.perFeedML ?? 0
        for kind in FeedKind.allCases where kind.usesVolume {
            FeedDefaults.setTypicalAmountML(
                FeedStats.typicalAmountML(entries, kind: kind),
                for: kind
            )
        }

        let snapshot = FeedSnapshot(
            lastFeed: lastFeed.map {
                FeedSnapshot.Feed(time: $0.startTime, kindRaw: $0.kindRaw, title: $0.kind.title, detail: $0.detailText(unit: unit))
            },
            nextFeedDue: AppSettings.remindersEnabled ? due : nil,
            last24hFeedCount: summary.feedCount,
            last24hVolumeText: unit.format(milliliters: summary.totalML),
            targetText: target.map { "~\(unit.format(milliliters: $0.targetML))" },
            babyName: profile.displayName,
            updatedAt: .now
        )
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()

        Task {
            await ReminderScheduler.reschedule(lastFeed: lastFeed, unit: unit, babyName: profile.displayName)
            await LiveActivityManager.update(
                lastFeed: lastFeed,
                dueDate: AppSettings.remindersEnabled ? due : nil,
                unit: unit,
                babyName: profile.displayName
            )
        }

        if triggerSync {
            SyncEngine.shared.requestSync()
        }
    }

    /// Weight, profile or settings changed. Same refresh; reads the new values.
    static func settingsDidChange(in context: ModelContext) {
        feedsDidChange(in: context)
    }

    /// A care note changed. Notes drive nothing derived — no widget snapshot,
    /// no reminder, no Live Activity — so this deliberately does less than
    /// `feedsDidChange` rather than recomputing all of it for nothing. It
    /// exists so every write in the app still funnels through one place.
    static func careNotesDidChange(in context: ModelContext) {
        try? context.save()
        SyncEngine.shared.requestSync()
    }

    /// Deletes are soft so they reach other caregivers' phones.
    static func delete(_ entry: FeedEntry, in context: ModelContext) {
        entry.softDelete()
        feedsDidChange(in: context)
    }

    static func delete(_ weight: WeightEntry, in context: ModelContext) {
        weight.softDelete()
        settingsDidChange(in: context)
    }

    static func delete(_ careNote: CareNote, in context: ModelContext) {
        careNote.softDelete()
        careNotesDidChange(in: context)
    }

    /// Newest-first, capped. The cap is across every baby on the phone; the
    /// caller narrows to one afterwards, which is why the limits above are
    /// generous rather than tight.
    private static func fetchRecent<T: PersistentModel>(
        _ type: T.Type,
        sortedBy keyPath: KeyPath<T, Date> & Sendable,
        limit: Int,
        in context: ModelContext
    ) -> [T] {
        var descriptor = FetchDescriptor<T>(sortBy: [SortDescriptor(keyPath, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

}
