import os
import SwiftData
import SwiftUI

/// Everything that happened, in one place: feeds, diapers, food, weigh-ins and
/// notes, by day, newest first, searchable ("when was the eye thing?"), and
/// with how long ago each day was, because that's how a doctor asks. Its
/// other half is the charts of the same log (`ChartsView`).
///
/// Named for what it is, not `TimelineView`, which SwiftUI already has.
struct CareTimelineView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case timeline = "Timeline"
        case charts = "Charts"
        var id: String { rawValue }
    }

    /// How far back browsing reaches at first, and how much each "Show
    /// earlier" adds. Search always looks through everything.
    static let windowStepDays = 30

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(AppRouter.self) private var router
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    @State private var query = ""
    @State private var windowDays = CareTimelineView.windowStepDays
    @State private var showSummary = false
    /// The oldest thing logged for this baby, so the pediatrician button and
    /// "Show earlier" only appear when there's something for them to show.
    @State private var earliest: Date?

    private var babyID: UUID? { UUID(uuidString: currentBabyIDRaw) }

    private var windowStart: Date {
        calendar.date(byAdding: .day, value: -(windowDays - 1), to: calendar.startOfDay(for: .now)) ?? .distantPast
    }

    /// Kept on the router, so something outside the Timeline can open it on
    /// its charts.
    private var mode: Binding<Mode> {
        Binding(
            get: { router.timelineShowsCharts ? .charts : .timeline },
            set: { router.timelineShowsCharts = $0 == .charts }
        )
    }

    private var modePicker: some View {
        Picker("View", selection: mode) {
            ForEach(Mode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    var body: some View {
        NavigationStack {
            Group {
                if router.timelineShowsCharts {
                    ChartsView(babyID: babyID) { modePicker }
                } else {
                    TimelineQueryView(
                        babyID: babyID,
                        since: query.isEmpty ? windowStart : nil,
                        query: query,
                        canShowEarlier: query.isEmpty && (earliest.map { $0 < windowStart } ?? false),
                        showEarlier: { windowDays += Self.windowStepDays }
                    ) {
                        modePicker
                    }
                }
            }
            .navigationTitle("Timeline")
            .searchable(text: $query, prompt: "Search notes, foods, names")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSummary = true
                    } label: {
                        Label("Summary for the pediatrician", systemImage: "stethoscope")
                    }
                    .disabled(earliest == nil)
                }
            }
            .sheet(isPresented: $showSummary) {
                SummarySheet()
            }
            .task(id: currentBabyIDRaw) {
                windowDays = Self.windowStepDays
                earliest = earliestEntry()
            }
            .onChange(of: router.tab) { _, tab in
                if tab == .timeline { earliest = earliestEntry() }
            }
            // A search is for finding an entry, which the list does.
            .onChange(of: query) { _, query in
                if !query.isEmpty { router.timelineShowsCharts = false }
            }
        }
    }

    /// One fetch per kind of entry, each limited to a single row.
    private func earliestEntry() -> Date? {
        let id = babyID
        func first<T: PersistentModel & CareEntry>(_ predicate: Predicate<T>, _ sort: SortDescriptor<T>) -> Date? {
            var descriptor = FetchDescriptor<T>(predicate: predicate, sortBy: [sort])
            descriptor.fetchLimit = 1
            return (try? modelContext.fetch(descriptor))?.first?.occurredAt
        }
        var dates: [Date?] = []
        dates.append(first(#Predicate<FeedEntry> { $0.babyID == id && $0.deletedAt == nil }, SortDescriptor(\.startTime)))
        dates.append(first(#Predicate<DiaperEntry> { $0.babyID == id && $0.deletedAt == nil }, SortDescriptor(\.time)))
        dates.append(first(#Predicate<SolidFoodEntry> { $0.babyID == id && $0.deletedAt == nil }, SortDescriptor(\.time)))
        dates.append(first(#Predicate<WeightEntry> { $0.babyID == id && $0.deletedAt == nil }, SortDescriptor(\.date)))
        dates.append(first(#Predicate<CareNote> { $0.babyID == id && $0.deletedAt == nil }, SortDescriptor(\.date)))
        dates.append(first(#Predicate<HealthConcern> { $0.babyID == id && $0.deletedAt == nil }, SortDescriptor(\.startedAt)))
        dates.append(first(#Predicate<MedicationDose> { $0.babyID == id && $0.deletedAt == nil }, SortDescriptor(\.time)))
        dates.append(first(#Predicate<DoctorVisit> { $0.babyID == id && $0.deletedAt == nil }, SortDescriptor(\.date)))
        return dates.compactMap { $0 }.min()
    }
}

/// The part that queries. Its queries are built in `init` from the window,
/// so browsing fetches a month of rows rather than the whole log, and a wider
/// window (or a search) swaps them for wider ones without resetting the list.
private struct TimelineQueryView<ModePicker: View>: View {
    let babyID: UUID?
    let since: Date?
    let query: String
    let canShowEarlier: Bool
    let showEarlier: () -> Void
    let modePicker: ModePicker

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    @Query private var feeds: [FeedEntry]
    @Query private var diapers: [DiaperEntry]
    @Query private var weights: [WeightEntry]
    @Query private var notes: [CareNote]
    @Query private var concerns: [HealthConcern]
    @Query private var doses: [MedicationDose]
    @Query private var visits: [DoctorVisit]
    /// Not windowed: whether a food is a first time depends on the whole log.
    @Query private var foods: [SolidFoodEntry]

    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue

    /// Older days the parent has tapped open.
    @State private var expandedDays: Set<Date> = []

    /// Building the days is on the main thread on every change; this marks it
    /// in Instruments so it can be held to its budget (under 16 ms for 30 days).
    private static var signposter: OSSignposter { OSSignposter(subsystem: "com.babyfeed.BabyFeed", category: "Timeline") }

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces }

    init(
        babyID: UUID?,
        since: Date?,
        query: String,
        canShowEarlier: Bool,
        showEarlier: @escaping () -> Void,
        @ViewBuilder modePicker: () -> ModePicker
    ) {
        self.babyID = babyID
        self.since = since
        self.query = query
        self.canShowEarlier = canShowEarlier
        self.showEarlier = showEarlier
        self.modePicker = modePicker()

        let start = since ?? .distantPast
        let id = babyID
        _feeds = Query(filter: #Predicate<FeedEntry> { $0.babyID == id && $0.deletedAt == nil && $0.startTime >= start },
                       sort: \.startTime, order: .reverse)
        _diapers = Query(filter: #Predicate<DiaperEntry> { $0.babyID == id && $0.deletedAt == nil && $0.time >= start },
                         sort: \.time, order: .reverse)
        _weights = Query(filter: #Predicate<WeightEntry> { $0.babyID == id && $0.deletedAt == nil && $0.date >= start },
                         sort: \.date, order: .reverse)
        _notes = Query(filter: #Predicate<CareNote> { $0.babyID == id && $0.deletedAt == nil && $0.date >= start },
                       sort: \.date, order: .reverse)
        _foods = Query(filter: #Predicate<SolidFoodEntry> { $0.babyID == id && $0.deletedAt == nil },
                       sort: \.time, order: .reverse)
        _concerns = Query(filter: #Predicate<HealthConcern> { $0.babyID == id && $0.deletedAt == nil && $0.startedAt >= start },
                          sort: \.startedAt, order: .reverse)
        _doses = Query(filter: #Predicate<MedicationDose> { $0.babyID == id && $0.deletedAt == nil && $0.time >= start },
                       sort: \.time, order: .reverse)
        _visits = Query(filter: #Predicate<DoctorVisit> { $0.babyID == id && $0.deletedAt == nil && $0.date >= start },
                        sort: \.date, order: .reverse)
    }

    var body: some View {
        let sources = TimelineSources(feeds: feeds, diapers: diapers, foods: foods, weights: weights, notes: notes,
                                      concerns: concerns, doses: doses, visits: visits)
        let categories = TimelineBuilder.categoriesPresent(sources, babyID: babyID)
        let days = Self.signposter.withIntervalSignpost("Build days") {
            let start = since ?? .distantPast
            // Foods come unwindowed (for the first-time flag), so the window
            // is applied to them here.
            let items = TimelineBuilder.items(sources, babyID: babyID, filter: router.timelineFilter, query: query)
                .filter { $0.date >= start }
            return TimelineBuilder.days(items, calendar: calendar)
        }
        let now = Date.now

        List {
            Section {
                modePicker
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            if categories.count > 1 || router.timelineFilter != .all {
                Section {
                    chips(categories)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }

            ForEach(days) { day in
                if isExpanded(day, now: now) {
                    Section {
                        if !day.feeds.isEmpty || !day.diapers.isEmpty {
                            DayStrip(feeds: day.feeds, diapers: day.diapers, day: day.day, calendar: calendar)
                                .padding(.vertical, 6)
                        }
                        ForEach(day.items) { item in
                            row(item)
                        }
                    } header: {
                        header(for: day, now: now)
                    }
                } else {
                    Section {
                        collapsedDay(day, now: now)
                    }
                }
            }

            if canShowEarlier {
                Section {
                    Button("Show earlier (\(CareTimelineView.windowStepDays) days)", action: showEarlier)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .overlay {
            if days.isEmpty {
                emptyState(hasAnything: !categories.isEmpty)
            }
        }
    }

    // MARK: Days

    /// Searching or filtering shows every match. Browsing shows today and
    /// yesterday in full, and older days as one summary line until tapped:
    /// thirty days of every diaper is a lot to scroll past to find a Monday.
    private func isExpanded(_ day: TimelineDay, now: Date) -> Bool {
        if !query.isEmpty || router.timelineFilter != .all { return true }
        if !isOlder(day, now: now) { return true }
        return expandedDays.contains(day.day)
    }

    private func isOlder(_ day: TimelineDay, now: Date) -> Bool {
        RelativeAge.days(from: day.day, to: now, calendar: calendar) >= 2
    }

    private func dayTitle(_ day: TimelineDay, now: Date) -> String {
        let title = FeedStats.dayTitle(for: day.day, calendar: calendar, now: now)
        guard isOlder(day, now: now) else { return title }
        return "\(title) · \(RelativeAge.ago(day.day, now: now, calendar: calendar))"
    }

    @ViewBuilder
    private func header(for day: TimelineDay, now: Date) -> some View {
        let canFold = isOlder(day, now: now) && query.isEmpty && router.timelineFilter == .all
        let summary = EntryRow.wrappingAtDots(day.summaryText(unit: unit))
        let label = HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                // Color.primary, not .primary: in a section header .primary
                // resolves against the header's own grey and comes out grey.
                Text(dayTitle(day, now: now))
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                if !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
            }
            Spacer()
            if canFold {
                Image(systemName: "chevron.up")
                    .font(.footnote.weight(.semibold))
            }
        }
        .textCase(nil)
        .padding(.bottom, 4)

        // Only an older day that was opened folds back up; today and
        // yesterday are always open, so their headers are just headers.
        if canFold {
            Button {
                withAnimation { _ = expandedDays.remove(day.day) }
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Folds this day back into one line")
        } else {
            label
        }
    }

    private func collapsedDay(_ day: TimelineDay, now: Date) -> some View {
        Button {
            withAnimation { _ = expandedDays.insert(day.day) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayTitle(day, now: now))
                        .font(.headline)
                    Text(EntryRow.wrappingAtDots(day.summaryText(unit: unit)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows this day's entries")
    }

    private func row(_ item: TimelineItem) -> some View {
        Button {
            router.sheet = .editEntry(item.ref)
        } label: {
            TimelineRow(item: item, unit: unit, weightUnit: weightUnit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) {
                delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: Filter chips

    private func chips(_ present: [TimelineCategory]) -> some View {
        // The selected chip stays even once it has nothing left to show, so
        // there's always a way back to All.
        var categories = present
        if case .only(let selected) = router.timelineFilter, !categories.contains(selected) {
            categories.append(selected)
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.all)
                ForEach(categories) { category in
                    chip(.only(category))
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(_ filter: TimelineFilter) -> some View {
        let selected = router.timelineFilter == filter
        return Button {
            router.timelineFilter = filter
        } label: {
            Text(filter.title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Empty states

    @ViewBuilder
    private func emptyState(hasAnything: Bool) -> some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if !hasAnything {
            ContentUnavailableView(
                "Nothing logged yet",
                systemImage: "list.bullet.clipboard",
                description: Text("Feeds, diapers, food and notes show up here, by day.")
            )
        } else if router.timelineFilter != .all {
            ContentUnavailableView(
                "No \(router.timelineFilter.title.lowercased()) lately",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Nothing of that kind in this stretch. Tap All to see everything.")
            )
        }
    }

    // MARK: Actions

    private func delete(_ item: TimelineItem) {
        toasts.delete(item, context: modelContext)
    }
}

#Preview {
    CareTimelineView()
        .environment(AppRouter())
        .environment(ToastCenter())
        .modelContainer(.preview)
}
