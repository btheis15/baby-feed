import SwiftData
import SwiftUI

/// The last few things logged, of any kind: "did anyone change her?" at a
/// glance, and the way into the Timeline for the rest.
struct RecentSection: View {
    let babyID: UUID?
    let unit: VolumeUnit
    let weightUnit: WeightUnit

    static let count = 3

    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    // A few rows of each kind, not the whole log: the newest three of
    // everything are always among the newest three of each.
    @Query private var feeds: [FeedEntry]
    @Query private var diapers: [DiaperEntry]
    @Query private var foods: [SolidFoodEntry]
    @Query private var weights: [WeightEntry]
    @Query private var notes: [CareNote]

    init(babyID: UUID?, unit: VolumeUnit, weightUnit: WeightUnit) {
        self.babyID = babyID
        self.unit = unit
        self.weightUnit = weightUnit

        let id = babyID
        func newest<T: PersistentModel>(_ predicate: Predicate<T>, _ sort: SortDescriptor<T>) -> Query<T, [T]> {
            var descriptor = FetchDescriptor<T>(predicate: predicate, sortBy: [sort])
            descriptor.fetchLimit = Self.count
            return Query(descriptor)
        }
        _feeds = newest(#Predicate<FeedEntry> { $0.babyID == id && $0.deletedAt == nil }, SortDescriptor(\.startTime, order: .reverse))
        _diapers = newest(#Predicate<DiaperEntry> { $0.babyID == id && $0.deletedAt == nil }, SortDescriptor(\.time, order: .reverse))
        _foods = newest(#Predicate<SolidFoodEntry> { $0.babyID == id && $0.deletedAt == nil }, SortDescriptor(\.time, order: .reverse))
        _weights = newest(#Predicate<WeightEntry> { $0.babyID == id && $0.deletedAt == nil }, SortDescriptor(\.date, order: .reverse))
        _notes = newest(#Predicate<CareNote> { $0.babyID == id && $0.deletedAt == nil }, SortDescriptor(\.date, order: .reverse))
    }

    private var items: [TimelineItem] {
        let sources = TimelineSources(feeds: feeds, diapers: diapers, foods: foods, weights: weights, notes: notes)
        return TimelineBuilder.items(sources, babyID: babyID)
            .prefix(Self.count)
            // Three foods are too few to tell a first time from a repeat; the
            // Timeline, which has the whole log, is where that's shown.
            .map { (item: TimelineItem) -> TimelineItem in
                if case .food(let food, _) = item { return .food(food, isFirstTime: false) }
                return item
            }
    }

    var body: some View {
        let items = items
        if !items.isEmpty {
            Section("Recent") {
                ForEach(items) { item in
                    Button {
                        router.sheet = .editEntry(item.ref)
                    } label: {
                        TimelineRow(item: item, unit: unit, weightUnit: weightUnit, showsDay: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            toasts.delete(item, context: modelContext)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                Button {
                    router.openTimeline()
                } label: {
                    HStack {
                        Text("See all in Timeline")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
            }
        }
    }
}
