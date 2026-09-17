import Foundation
import SwiftData
import WidgetKit

/// The one place that reacts to data changing. Every save or delete funnels
/// through here so widgets, the reminder, the Live Activity and sync stay in step.
@MainActor
enum FeedCoordinator {
    static func feedsDidChange(in context: ModelContext, triggerSync: Bool = true) {
        try? context.save()

        let babyID = AppSettings.currentBabyID
        let allFeeds = (try? context.fetch(FetchDescriptor<FeedEntry>(sortBy: [SortDescriptor(\.startTime, order: .reverse)]))) ?? []
        let entries = allFeeds.active(for: babyID)

        let allWeights = (try? context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let weights = allWeights.active(for: babyID)

        let unit = AppSettings.volumeUnit
        let profile = BabyProfile.load()
        let lastFeed = entries.first
        let due = lastFeed.map { AppSettings.nextDue(after: $0.startTime) }

        let recent = FeedStats.entries(entries, within: 24 * 60 * 60)
        let summary = FeedSummary(recent)
        let target = FeedingGuidance.dailyTarget(
            weightGrams: weights.first?.grams,
            ageDays: profile.ageInDays(),
            style: AppSettings.feedingStyle,
            feedsPerDay: AppSettings.feedsPerDay
        )

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

    /// Deletes are soft so they reach other caregivers' phones.
    static func delete(_ entry: FeedEntry, in context: ModelContext) {
        entry.softDelete()
        feedsDidChange(in: context)
    }

    static func delete(_ weight: WeightEntry, in context: ModelContext) {
        weight.softDelete()
        settingsDidChange(in: context)
    }
}
