import Foundation
import SwiftData
import Testing
@testable import BabyFeed

/// The Timeline is the one place everything logged comes together, so what
/// it merges, leaves out and finds is pinned here, along with the day totals
/// its headers show, which must equal the numbers every other screen uses.
struct TimelineBuilderTests {
    private let baby = UUID()
    private let otherBaby = UUID()
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    /// Noon on Monday 2026-09-28, New York.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12))!
    }

    private func at(_ hoursAgo: Double) -> Date { now.addingTimeInterval(-hoursAgo * 3600) }

    // MARK: Merging

    @Test func everyKindMergesNewestFirst() {
        let sources = TimelineSources(
            feeds: [FeedEntry(babyID: baby, startTime: at(1), kind: .formula, amountML: 90)],
            diapers: [DiaperEntry(babyID: baby, time: at(0.5), kind: .wet)],
            foods: [SolidFoodEntry(babyID: baby, time: at(3), name: "Banana", texture: .puree)],
            weights: [WeightEntry(babyID: baby, date: at(26), grams: 3400)],
            notes: [CareNote(babyID: baby, date: at(2), kind: .rash, note: "red cheek")]
        )
        let items = TimelineBuilder.items(sources, babyID: baby)
        #expect(items.map(\.category) == [.diapers, .feeds, .notes, .food, .growth])
        #expect(items.map(\.date) == items.map(\.date).sorted(by: >))
    }

    @Test func onlyThisBabysUndeletedRowsAreShown() {
        let deleted = DiaperEntry(babyID: baby, time: at(1), kind: .dirty)
        deleted.softDelete()
        let sources = TimelineSources(
            feeds: [
                FeedEntry(babyID: baby, startTime: at(1), kind: .nursing, durationMinutes: 15),
                FeedEntry(babyID: otherBaby, startTime: at(2), kind: .formula, amountML: 60),
            ],
            diapers: [deleted, DiaperEntry(babyID: baby, time: at(3), kind: .wet)]
        )
        let items = TimelineBuilder.items(sources, babyID: baby)
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.entry.babyID == baby && $0.entry.deletedAt == nil })

        // No baby chosen (a fresh install) shows every baby's rows.
        #expect(TimelineBuilder.items(sources, babyID: nil).count == 3)
    }

    @Test func eachFilterShowsOnlyItsKind() {
        let sources = TimelineSources(
            feeds: [FeedEntry(babyID: baby, startTime: at(1), kind: .formula, amountML: 90)],
            diapers: [DiaperEntry(babyID: baby, time: at(2), kind: .wet)],
            foods: [SolidFoodEntry(babyID: baby, time: at(3), name: "Pear", texture: .puree)],
            weights: [WeightEntry(babyID: baby, date: at(4), grams: 3400)],
            notes: [CareNote(babyID: baby, date: at(5), kind: .sleep, note: "long nap")]
        )
        for category in TimelineCategory.allCases {
            let items = TimelineBuilder.items(sources, babyID: baby, filter: .only(category))
            #expect(items.count == 1, "\(category)")
            #expect(items.first?.category == category)
        }
        #expect(TimelineBuilder.items(sources, babyID: baby, filter: .all).count == 5)
    }

    @Test func aChipIsOnlyOfferedForKindsThatHaveRows() {
        let deletedNote = CareNote(babyID: baby, date: at(1), kind: .other, note: "gone")
        deletedNote.softDelete()
        let sources = TimelineSources(
            feeds: [FeedEntry(babyID: baby, startTime: at(1), kind: .formula, amountML: 90)],
            diapers: [DiaperEntry(babyID: otherBaby, time: at(2), kind: .wet)],
            notes: [deletedNote]
        )
        #expect(TimelineBuilder.categoriesPresent(sources, babyID: baby) == [.feeds])
    }

    // MARK: Search

    @Test func searchMatchesEveryWordInAnyOrderIgnoringCaseAndAccents() {
        let eye = CareNote(babyID: baby, date: at(30), kind: .other, note: "Red patch near her eye")
        let cafe = CareNote(babyID: baby, date: at(40), kind: .other, note: "Fussy after the café visit")
        let sources = TimelineSources(notes: [eye, cafe])

        #expect(TimelineBuilder.items(sources, babyID: baby, query: "eye").count == 1)
        #expect(TimelineBuilder.items(sources, babyID: baby, query: "EYE red").count == 1, "any order, any case")
        #expect(TimelineBuilder.items(sources, babyID: baby, query: "eye blue").isEmpty, "every word must match")
        #expect(TimelineBuilder.items(sources, babyID: baby, query: "cafe").count == 1, "accents don't matter")
        #expect(TimelineBuilder.items(sources, babyID: baby, query: "   ").count == 2, "blank is no search")
    }

    @Test func searchFindsKindsFoodsAndWhoLoggedIt() {
        let sources = TimelineSources(
            feeds: [FeedEntry(babyID: baby, startTime: at(1), kind: .nursing, durationMinutes: 10, side: .left, loggedByName: "Annette")],
            diapers: [DiaperEntry(babyID: baby, time: at(2), kind: .dirty)],
            foods: [SolidFoodEntry(babyID: baby, time: at(3), name: "Avocado", texture: .mashed)]
        )
        #expect(TimelineBuilder.items(sources, babyID: baby, query: "annette").map(\.category) == [.feeds])
        #expect(TimelineBuilder.items(sources, babyID: baby, query: "left").map(\.category) == [.feeds])
        #expect(TimelineBuilder.items(sources, babyID: baby, query: "dirty diaper").map(\.category) == [.diapers])
        #expect(TimelineBuilder.items(sources, babyID: baby, query: "avocado").map(\.category) == [.food])
    }

    // MARK: First times

    @Test func onlyTheEarliestOfEachFoodIsAFirstTime() {
        let first = SolidFoodEntry(babyID: baby, time: at(72), name: "Banana", texture: .puree)
        let again = SolidFoodEntry(babyID: baby, time: at(24), name: " banana ", texture: .puree)
        let other = SolidFoodEntry(babyID: baby, time: at(1), name: "Egg", texture: .puree)
        let items = TimelineBuilder.items(TimelineSources(foods: [again, other, first]), babyID: baby)

        let flags = items.compactMap { item -> (String, Bool)? in
            if case .food(let food, let isFirstTime) = item { return (food.name, isFirstTime) }
            return nil
        }
        #expect(flags.map(\.0) == ["Egg", " banana ", "Banana"])
        #expect(flags.map(\.1) == [true, false, true], "the second banana isn't new, however it was typed")
    }

    @Test func aDeletedFoodDoesNotCountAsHavingBeenTried() {
        let deleted = SolidFoodEntry(babyID: baby, time: at(72), name: "Peanut", texture: .puree)
        deleted.softDelete()
        let real = SolidFoodEntry(babyID: baby, time: at(1), name: "Peanut", texture: .puree)
        let items = TimelineBuilder.items(TimelineSources(foods: [deleted, real]), babyID: baby)
        guard case .food(_, let isFirstTime) = items.first else {
            Issue.record("expected the food")
            return
        }
        #expect(isFirstTime)
    }

    // MARK: Days

    @Test func dayTotalsAreTheSameNumbersTheRestOfTheAppShows() {
        let feeds = [
            FeedEntry(babyID: baby, startTime: at(1), kind: .formula, amountML: 90),
            FeedEntry(babyID: baby, startTime: at(3), kind: .nursing, durationMinutes: 12),
            FeedEntry(babyID: baby, startTime: at(26), kind: .breastMilk, amountML: 60),
        ]
        let diapers = [
            DiaperEntry(babyID: baby, time: at(2), kind: .both),
            DiaperEntry(babyID: baby, time: at(4), kind: .wet),
            DiaperEntry(babyID: baby, time: at(27), kind: .dirty),
        ]
        let items = TimelineBuilder.items(TimelineSources(feeds: feeds, diapers: diapers), babyID: baby)
        let days = TimelineBuilder.days(items, calendar: calendar)

        #expect(days.count == 2)
        let today = days[0]
        #expect(calendar.isDate(today.day, inSameDayAs: now))
        #expect(today.feedSummary == FeedSummary(Array(feeds.prefix(2))))
        #expect(today.diaperTally.wet == 2)
        #expect(today.diaperTally.dirty == 1)
        #expect(today.summaryText(unit: .milliliters)
                == "\(FeedSummary(Array(feeds.prefix(2))).text(unit: .milliliters)) · \(DiaperTally(Array(diapers.prefix(2))).text)")

        let yesterday = days[1]
        #expect(yesterday.feedSummary == FeedSummary([feeds[2]]))
        #expect(yesterday.diaperTally.dirty == 1)
    }

    @Test func aDaySummaryCountsTheQuieterKindsToo() {
        let items = TimelineBuilder.items(TimelineSources(
            foods: [SolidFoodEntry(babyID: baby, time: at(1), name: "Oats", texture: .puree),
                    SolidFoodEntry(babyID: baby, time: at(2), name: "Pear", texture: .puree)],
            weights: [WeightEntry(babyID: baby, date: at(3), grams: 3400)],
            notes: [CareNote(babyID: baby, date: at(4), kind: .other, note: "hiccups")]
        ), babyID: baby)
        let day = TimelineBuilder.days(items, calendar: calendar)[0]
        #expect(day.summaryText(unit: .ounces) == "1 note · 2 foods · weigh-in")
    }

    @Test func toastsNameWhatWasLogged() {
        #expect(TimelineItem.feed(FeedEntry(kind: .formula)).shortTitle == "Formula feed")
        #expect(TimelineItem.diaper(DiaperEntry(kind: .both)).shortTitle == "Wet and dirty diaper")
        #expect(TimelineItem.food(SolidFoodEntry(name: "Pear", texture: .puree), isFirstTime: true).shortTitle == "Pear")
        #expect(TimelineItem.weight(WeightEntry(grams: 3000)).shortTitle == "Weigh-in")
        #expect(TimelineItem.note(CareNote(kind: .rash)).shortTitle == "Note")
    }

    // MARK: Budget

    /// The days are rebuilt on the main thread whenever anything changes, so
    /// a month of a busy newborn's log has to build inside one frame.
    @Test @MainActor func aMonthOfEntriesBuildsInsideAFrame() throws {
        let container = try AppSchema.inMemoryContainer()
        let context = container.mainContext
        var sources = TimelineSources()
        for day in 0..<30 {
            for slot in 0..<10 {
                let feed = FeedEntry(babyID: baby, startTime: at(Double(day * 24 + slot * 2)), kind: .formula, amountML: 90)
                context.insert(feed)
                sources.feeds.append(feed)
            }
            for slot in 0..<8 {
                let diaper = DiaperEntry(babyID: baby, time: at(Double(day * 24 + slot * 3) + 0.5), kind: .wet)
                context.insert(diaper)
                sources.diapers.append(diaper)
            }
            let note = CareNote(babyID: baby, date: at(Double(day * 24) + 5), kind: .other, note: "note \(day)")
            context.insert(note)
            sources.notes.append(note)
        }
        try context.save()

        let clock = ContinuousClock()
        var fastest = Duration.seconds(1)
        for _ in 0..<5 {
            let elapsed = clock.measure {
                let items = TimelineBuilder.items(sources, babyID: baby)
                _ = TimelineBuilder.days(items, calendar: calendar)
            }
            fastest = min(fastest, elapsed)
        }
        #expect(fastest < .milliseconds(16), "took \(fastest)")
    }
}
