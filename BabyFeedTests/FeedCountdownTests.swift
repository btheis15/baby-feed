import Foundation
import Testing
@testable import BabyFeed

/// The countdown is the first thing on screen and appears in five places, so
/// its edges are pinned: when it flips to overdue, how it rounds, and when it
/// gives up and goes quiet.
struct FeedCountdownTests {
    private let lastFeed = Date(timeIntervalSince1970: 1_800_000_000)
    private let interval = 180

    private func state(minutesAfterFeed minutes: Double) -> FeedCountdown {
        FeedCountdown.state(lastFeed: lastFeed, intervalMinutes: interval, now: lastFeed.addingTimeInterval(minutes * 60))
    }

    private var due: Date { lastFeed.addingTimeInterval(Double(interval) * 60) }

    @Test func nothingLoggedIsNoFeeds() {
        #expect(FeedCountdown.state(lastFeed: nil, intervalMinutes: interval, now: .now) == .noFeeds)
    }

    @Test func minutesLeftRoundUpSoItNeverReadsZeroBeforeItsDue() {
        // 30 seconds before due: "1m", not "0m".
        #expect(state(minutesAfterFeed: 179.5) == .upcoming(due: due, minutesLeft: 1))
        // 1h 19m 30s before due reads as "1h 20m".
        let early = state(minutesAfterFeed: 180 - 79.5)
        #expect(early == .upcoming(due: due, minutesLeft: 80))
        #expect(ElapsedText.compact(minutes: 80) == "1h 20m")
        // Right after the feed, the whole interval.
        #expect(state(minutesAfterFeed: 0) == .upcoming(due: due, minutesLeft: 180))
    }

    @Test func exactlyAtTheDueTimeItIsDue() {
        #expect(state(minutesAfterFeed: 180) == .overdue(due: due, minutesLate: 0))
        #expect(state(minutesAfterFeed: 205.9) == .overdue(due: due, minutesLate: 25))
    }

    @Test func aWholeIntervalLateIsStillOverdueAndThenItGoesQuiet() {
        #expect(state(minutesAfterFeed: 360) == .overdue(due: due, minutesLate: 180))
        #expect(state(minutesAfterFeed: 361) == .quiet(lastFeed: lastFeed))
        // A feed from yesterday reads as quiet, not "overdue 20 hours".
        #expect(state(minutesAfterFeed: 24 * 60).isQuiet)
    }

    @Test func aFeedStampedInTheFutureStillReadsAsOneIntervalAway() {
        // The other phone's clock runs two minutes fast.
        let now = lastFeed.addingTimeInterval(-120)
        #expect(FeedCountdown.state(lastFeed: lastFeed, intervalMinutes: interval, now: now)
            == .upcoming(due: due, minutesLeft: 180))
    }

    @Test func theWidgetGetsTheSameAnswerFromTheDueTimeAlone() {
        for minutes in [0.0, 90, 179.5, 180, 250, 361] {
            let now = lastFeed.addingTimeInterval(minutes * 60)
            #expect(FeedCountdown.state(lastFeed: lastFeed, due: due, now: now)
                == FeedCountdown.state(lastFeed: lastFeed, intervalMinutes: interval, now: now), "\(minutes) minutes in")
        }
        #expect(FeedCountdown.state(lastFeed: nil, due: nil, now: .now) == .noFeeds)
    }

    @Test func theWidgetNeedsEntriesOnlyWhereTheStateChanges() {
        let now = lastFeed.addingTimeInterval(60 * 60)
        let transitions = FeedCountdown.transitions(lastFeed: lastFeed, due: due, after: now)
        #expect(transitions.count == 2)
        #expect(transitions[0] == due)
        #expect(FeedCountdown.state(lastFeed: lastFeed, due: due, now: transitions[1]).isQuiet)
        #expect(FeedCountdown.state(lastFeed: lastFeed, due: due, now: transitions[1].addingTimeInterval(-61)).isOverdue)
        // Once quiet, nothing is left to change.
        #expect(FeedCountdown.transitions(lastFeed: lastFeed, due: due, after: transitions[1]).isEmpty)
    }

    @Test func dueIsOnlyThereWhenThereIsSomethingToCountTo() {
        #expect(state(minutesAfterFeed: 10).due == due)
        #expect(state(minutesAfterFeed: 200).due == due)
        #expect(state(minutesAfterFeed: 400).due == nil)
        #expect(FeedCountdown.noFeeds.due == nil)
    }

    @Test func spokenDurationsReadAsWords() {
        #expect(ElapsedText.spoken(minutes: 80) == "1 hour 20 minutes")
        #expect(ElapsedText.spoken(minutes: 60) == "1 hour")
        #expect(ElapsedText.spoken(minutes: 1) == "1 minute")
        #expect(ElapsedText.spoken(minutes: 0) == "0 minutes")
        #expect(ElapsedText.spoken(minutes: 125) == "2 hours 5 minutes")
    }

    @Test func clockTimesFollowThePinnedTimeZone() throws {
        let chicago = try #require(TimeZone(identifier: "America/Chicago"))
        let london = try #require(TimeZone(identifier: "Europe/London"))
        // Six hours apart in January, so the same moment reads differently.
        let moment = Date(timeIntervalSince1970: 1_799_000_000) // 2027-01-03 18:13 UTC
        #expect(ClockText.time(moment, in: chicago) != ClockText.time(moment, in: london))
    }

    @Test func sinceSaysTodayYesterdayOrTheDate() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let now = Date(timeIntervalSince1970: 1_800_000_000) // Fri 2027-01-15 08:00 UTC
        let earlierToday = now.addingTimeInterval(-3 * 3600)
        let yesterday = now.addingTimeInterval(-26 * 3600)
        let lastWeek = now.addingTimeInterval(-6 * 86_400)
        #expect(ClockText.since(earlierToday, now: now, in: utc) == ClockText.time(earlierToday, in: utc))
        #expect(ClockText.since(yesterday, now: now, in: utc).hasPrefix("yesterday, "))
        #expect(!ClockText.since(lastWeek, now: now, in: utc).contains("yesterday"))
    }
}

@MainActor
struct ReminderSnoozeTests {
    private let feed = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aSnoozeSurvivesTheAppBeingOpened() {
        #expect(ReminderScheduler.keepsSnooze(
            snoozedUntil: feed.addingTimeInterval(4 * 3600),
            snoozedForFeedAt: feed,
            lastFeedStart: feed,
            now: feed.addingTimeInterval(3 * 3600 + 60)
        ))
    }

    @Test func aNewFeedCancelsTheSnooze() {
        #expect(!ReminderScheduler.keepsSnooze(
            snoozedUntil: feed.addingTimeInterval(4 * 3600),
            snoozedForFeedAt: feed,
            lastFeedStart: feed.addingTimeInterval(3 * 3600 + 30),
            now: feed.addingTimeInterval(3 * 3600 + 60)
        ))
    }

    @Test func aSnoozeThatHasGoneOffIsOver() {
        #expect(!ReminderScheduler.keepsSnooze(
            snoozedUntil: feed.addingTimeInterval(3 * 3600),
            snoozedForFeedAt: feed,
            lastFeedStart: feed,
            now: feed.addingTimeInterval(3 * 3600 + 1)
        ))
        #expect(!ReminderScheduler.keepsSnooze(snoozedUntil: nil, snoozedForFeedAt: feed, lastFeedStart: feed, now: feed))
    }
}
