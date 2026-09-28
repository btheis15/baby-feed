import Foundation
import SwiftData
import SwiftUI

/// Kinds of thing on the timeline, for the filter chips.
enum TimelineCategory: String, CaseIterable, Identifiable {
    case feeds, diapers, food, notes, growth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feeds: "Feeds"
        case .diapers: "Diapers"
        case .food: "Food"
        case .notes: "Notes"
        case .growth: "Growth"
        }
    }

    var systemImage: String {
        switch self {
        case .feeds: "waterbottle.fill"
        case .diapers: "drop.halffull"
        case .food: "carrot.fill"
        case .notes: "note.text"
        case .growth: "scalemass.fill"
        }
    }
}

/// Everything, or one kind of thing.
enum TimelineFilter: Hashable, Identifiable {
    case all
    case only(TimelineCategory)

    var id: String {
        switch self {
        case .all: "all"
        case .only(let category): category.rawValue
        }
    }

    var title: String {
        switch self {
        case .all: "All"
        case .only(let category): category.title
        }
    }

    func includes(_ category: TimelineCategory) -> Bool {
        switch self {
        case .all: true
        case .only(let only): only == category
        }
    }
}

/// Points at one row of the log without holding it, so a sheet can be asked
/// to edit it from anywhere — a timeline row, or the Edit on a toast.
enum EntryRef: Hashable, Identifiable {
    case feed(PersistentIdentifier)
    case diaper(PersistentIdentifier)
    case food(PersistentIdentifier)
    case weight(PersistentIdentifier)
    case note(PersistentIdentifier)

    var id: String {
        switch self {
        case .feed(let id): "feed:\(id.hashValue)"
        case .diaper(let id): "diaper:\(id.hashValue)"
        case .food(let id): "food:\(id.hashValue)"
        case .weight(let id): "weight:\(id.hashValue)"
        case .note(let id): "note:\(id.hashValue)"
        }
    }
}

/// One row of the timeline, whatever it records. An enum rather than a
/// protocol so that adding a kind of entry makes every `switch` over it —
/// the row, the editor, search — refuse to compile until it's handled.
enum TimelineItem: Identifiable {
    case feed(FeedEntry)
    case diaper(DiaperEntry)
    case food(SolidFoodEntry, isFirstTime: Bool)
    case weight(WeightEntry)
    case note(CareNote)

    var entry: any CareEntry {
        switch self {
        case .feed(let entry): entry
        case .diaper(let entry): entry
        case .food(let entry, _): entry
        case .weight(let entry): entry
        case .note(let entry): entry
        }
    }

    var id: String {
        let key = entry.uuid?.uuidString ?? ObjectIdentifier(entry).debugDescription
        switch self {
        case .feed: return "feed:\(key)"
        case .diaper: return "diaper:\(key)"
        case .food: return "food:\(key)"
        case .weight: return "weight:\(key)"
        case .note: return "note:\(key)"
        }
    }

    var date: Date { entry.occurredAt }

    var systemImage: String {
        switch self {
        case .feed(let feed): feed.kind.systemImage
        case .diaper(let diaper): diaper.kind.systemImage
        case .food(let food, _): food.reaction.systemImage
        case .weight: "scalemass.fill"
        case .note(let note): note.kind.systemImage
        }
    }

    var tint: Color {
        switch self {
        case .feed(let feed): feed.kind.color
        case .diaper(let diaper): diaper.kind.color
        // "Ate it" is drawn in grey in the food picker; a grey dot in a
        // list of coloured ones reads as disabled.
        case .food(let food, _): food.reaction.color == .secondary ? .green : food.reaction.color
        case .weight: .blue
        case .note: .purple
        }
    }

    /// A few words naming the entry, for a toast: "Formula feed", "Wet diaper",
    /// "Banana", "Weigh-in", "Note".
    var shortTitle: String {
        switch self {
        case .feed(let feed): "\(feed.kind.title) feed"
        case .diaper(let diaper): diaper.kind.entryTitle
        case .food(let food, _): food.name.isEmpty ? "Food" : food.name
        case .weight: "Weigh-in"
        case .note: "Note"
        }
    }

    var category: TimelineCategory {
        switch self {
        case .feed: .feeds
        case .diaper: .diapers
        case .food: .food
        case .weight: .growth
        case .note: .notes
        }
    }

    var ref: EntryRef {
        switch self {
        case .feed(let entry): .feed(entry.persistentModelID)
        case .diaper(let entry): .diaper(entry.persistentModelID)
        case .food(let entry, _): .food(entry.persistentModelID)
        case .weight(let entry): .weight(entry.persistentModelID)
        case .note(let entry): .note(entry.persistentModelID)
        }
    }

    /// Everything a search should find this by: what it was, what was
    /// written about it, and who logged it.
    var searchText: String {
        var parts: [String] = [entry.loggedByName]
        switch self {
        case .feed(let feed):
            parts += [feed.kind.title, "feed", feed.note, feed.side?.title ?? ""]
        case .diaper(let diaper):
            parts += [diaper.kind.title, "diaper", diaper.note]
        case .food(let food, let isFirstTime):
            parts += [food.name, "food", food.texture.title, food.reaction.title, food.note, isFirstTime ? "first time" : ""]
        case .weight(let weight):
            parts += ["weight", "weigh-in", weight.note]
        case .note(let note):
            parts += [note.kind.title, "note", note.note, note.severity?.title ?? ""]
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// The rows to build a timeline from, straight from the store.
struct TimelineSources {
    var feeds: [FeedEntry] = []
    var diapers: [DiaperEntry] = []
    var foods: [SolidFoodEntry] = []
    var weights: [WeightEntry] = []
    var notes: [CareNote] = []
}

/// One day of the timeline, with the tallies its header shows.
struct TimelineDay: Identifiable {
    let day: Date
    let items: [TimelineItem]
    var id: Date { day }

    var feeds: [FeedEntry] {
        items.compactMap { if case .feed(let feed) = $0 { feed } else { nil } }
    }

    var diapers: [DiaperEntry] {
        items.compactMap { if case .diaper(let diaper) = $0 { diaper } else { nil } }
    }

    var feedSummary: FeedSummary { FeedSummary(feeds) }
    var diaperTally: DiaperTally { DiaperTally(diapers) }

    /// "9 feeds · 14 oz · 7 wet · 4 dirty · 1 note": what the day's header,
    /// or the day folded into one line, says about it.
    func summaryText(unit: VolumeUnit) -> String {
        var parts: [String] = []
        let feeds = feeds
        if !feeds.isEmpty { parts.append(FeedSummary(feeds).text(unit: unit)) }
        let tally = diaperTally
        if !tally.isEmpty { parts.append(tally.text) }
        let counts = Dictionary(grouping: items, by: \.category).mapValues(\.count)
        func counted(_ category: TimelineCategory, _ one: String, _ many: String) {
            guard let count = counts[category], count > 0 else { return }
            parts.append(count == 1 ? one : "\(count) \(many)")
        }
        counted(.notes, "1 note", "notes")
        counted(.food, "1 food", "foods")
        counted(.growth, "weigh-in", "weigh-ins")
        return parts.joined(separator: " · ")
    }
}

enum TimelineBuilder {
    /// Every active row for the baby, newest first, narrowed by the filter
    /// and the search. Searching matches every word typed, in any order,
    /// ignoring case and accents, so "eye red" finds "Red patch near her eye".
    static func items(
        _ sources: TimelineSources,
        babyID: UUID?,
        filter: TimelineFilter = .all,
        query: String = ""
    ) -> [TimelineItem] {
        var items: [TimelineItem] = []
        if filter.includes(.feeds) {
            items += sources.feeds.active(for: babyID).map(TimelineItem.feed)
        }
        if filter.includes(.diapers) {
            items += sources.diapers.active(for: babyID).map(TimelineItem.diaper)
        }
        if filter.includes(.food) {
            // First times are judged against the whole food log, not just what
            // the window shows, and worked out once rather than per row.
            let foods = sources.foods.active(for: babyID)
            let firsts = firstTimeIDs(foods)
            items += foods.map { TimelineItem.food($0, isFirstTime: firsts.contains(ObjectIdentifier($0))) }
        }
        if filter.includes(.growth) {
            items += sources.weights.active(for: babyID).map(TimelineItem.weight)
        }
        if filter.includes(.notes) {
            items += sources.notes.active(for: babyID).map(TimelineItem.note)
        }

        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if !words.isEmpty {
            items = items.filter { item in
                let haystack = item.searchText
                return words.allSatisfy { haystack.localizedStandardContains($0) }
            }
        }
        // Dates read once each, for the same reason as in DayGrouping.
        return items
            .map { (date: $0.date, item: $0) }
            .sorted { $0.date > $1.date }
            .map(\.item)
    }

    static func days(_ items: [TimelineItem], calendar: Calendar) -> [TimelineDay] {
        DayGrouping.group(items, calendar: calendar) { $0.date }
            .map { TimelineDay(day: $0.day, items: $0.items) }
    }

    /// The categories that have anything in them, so a chip is only offered
    /// when tapping it would show something.
    static func categoriesPresent(_ sources: TimelineSources, babyID: UUID?) -> [TimelineCategory] {
        TimelineCategory.allCases.filter { category in
            switch category {
            case .feeds: !sources.feeds.active(for: babyID).isEmpty
            case .diapers: !sources.diapers.active(for: babyID).isEmpty
            case .food: !sources.foods.active(for: babyID).isEmpty
            case .growth: !sources.weights.active(for: babyID).isEmpty
            case .notes: !sources.notes.active(for: babyID).isEmpty
            }
        }
    }

    /// The earliest entry of each food, by name, ignoring case and spacing.
    private static func firstTimeIDs(_ foods: [SolidFoodEntry]) -> Set<ObjectIdentifier> {
        var seen = Set<String>()
        var firsts = Set<ObjectIdentifier>()
        for food in foods.sorted(by: { $0.time < $1.time }) {
            let key = food.normalizedName
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            firsts.insert(ObjectIdentifier(food))
        }
        return firsts
    }
}
