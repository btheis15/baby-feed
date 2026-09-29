import Accessibility
import Charts
import SwiftData
import SwiftUI

/// The Timeline's charts. Each one is led by a sentence that states its
/// number, worked out by `CareCharts` from the same series the chart draws,
/// so nothing has to be read off an axis at 3 a.m. That squinting is why
/// commit ce11c14 took the old charts out. The plain numbers stay underneath.
struct ChartsView<ModePicker: View>: View {
    let babyID: UUID?
    let modePicker: ModePicker

    @Environment(\.calendar) private var calendar
    @SceneStorage("charts.range") private var rangeRaw = ChartRange.twoWeeks.rawValue
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0
    /// Every visit, not only the range's: "since the last visit" needs the
    /// last one to know where to start.
    @Query private var visits: [DoctorVisit]

    init(babyID: UUID?, @ViewBuilder modePicker: () -> ModePicker) {
        self.babyID = babyID
        self.modePicker = modePicker()
        let id = babyID
        _visits = Query(filter: #Predicate<DoctorVisit> { $0.babyID == id && $0.deletedAt == nil },
                        sort: \.date, order: .reverse)
    }

    var body: some View {
        let now = Date.now
        let lastVisit = visits.first { $0.date <= now }?.date
        let range = (ChartRange(rawValue: rangeRaw) ?? .twoWeeks).effective(lastVisit: lastVisit)
        let birthDate = birthInterval > 0 ? Date(timeIntervalSince1970: birthInterval) : nil
        ChartsList(
            babyID: babyID,
            range: range,
            interval: range.interval(now: now, lastVisit: lastVisit, birthDate: birthDate, calendar: calendar),
            lastVisit: lastVisit,
            visits: visits,
            now: now,
            rangeRaw: $rangeRaw,
            modePicker: modePicker
        )
    }
}

/// The part that queries, built in `init` from the range so three months of
/// charts fetch three months of rows, not the whole log.
private struct ChartsList<ModePicker: View>: View {
    let babyID: UUID?
    let range: ChartRange
    let interval: DateInterval
    let lastVisit: Date?
    let visits: [DoctorVisit]
    let now: Date
    @Binding var rangeRaw: String
    let modePicker: ModePicker

    @Environment(\.calendar) private var calendar
    @Environment(AppRouter.self) private var router

    @Query private var feeds: [FeedEntry]
    @Query private var diapers: [DiaperEntry]
    @Query private var doses: [MedicationDose]
    @Query private var notes: [CareNote]
    /// Not windowed: each day's target needs the latest weigh-in before it,
    /// however long ago that was.
    @Query private var weights: [WeightEntry]
    /// Not windowed: a concern that started before the range can still be going.
    @Query private var concerns: [HealthConcern]
    /// Not windowed: whether a food is a first time depends on the whole log.
    @Query private var foods: [SolidFoodEntry]

    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue
    @AppStorage(AppSettings.feedingStyleKey) private var feedingStyleRaw = FeedingStyle.formula.rawValue
    @AppStorage(AppSettings.feedsPerDayKey) private var feedsPerDay = 0
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0
    @AppStorage(BabyProfile.nameKey) private var babyName = ""
    @AppStorage(BabyProfile.sexKey) private var sexRaw = BabySex.unspecified.rawValue
    @AppStorage(BabyProfile.dueDateKey) private var dueInterval: Double = 0

    /// Where the care chart was last tapped. That day's entries list under it.
    @State private var selection: Date?

    init(
        babyID: UUID?,
        range: ChartRange,
        interval: DateInterval,
        lastVisit: Date?,
        visits: [DoctorVisit],
        now: Date,
        rangeRaw: Binding<String>,
        modePicker: ModePicker
    ) {
        self.babyID = babyID
        self.range = range
        self.interval = interval
        self.lastVisit = lastVisit
        self.visits = visits
        self.now = now
        _rangeRaw = rangeRaw
        self.modePicker = modePicker

        let id = babyID
        let start = interval.start
        // The numbers underneath compare the last 7 complete days with the 7
        // before them, whatever the range, so feeds reach back a month at least.
        let feedStart = min(start, now.addingTimeInterval(-31 * 86_400))
        _feeds = Query(filter: #Predicate<FeedEntry> { $0.babyID == id && $0.deletedAt == nil && $0.startTime >= feedStart },
                       sort: \.startTime, order: .reverse)
        _diapers = Query(filter: #Predicate<DiaperEntry> { $0.babyID == id && $0.deletedAt == nil && $0.time >= start },
                         sort: \.time, order: .reverse)
        _doses = Query(filter: #Predicate<MedicationDose> { $0.babyID == id && $0.deletedAt == nil && $0.time >= start },
                       sort: \.time, order: .reverse)
        _notes = Query(filter: #Predicate<CareNote> { $0.babyID == id && $0.deletedAt == nil && $0.date >= start },
                       sort: \.date, order: .reverse)
        _weights = Query(filter: #Predicate<WeightEntry> { $0.babyID == id && $0.deletedAt == nil },
                         sort: \.date, order: .reverse)
        _concerns = Query(filter: #Predicate<HealthConcern> { $0.babyID == id && $0.deletedAt == nil },
                          sort: \.startedAt, order: .reverse)
        _foods = Query(filter: #Predicate<SolidFoodEntry> { $0.babyID == id && $0.deletedAt == nil },
                       sort: \.time, order: .reverse)
    }

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces }
    private var style: FeedingStyle { FeedingStyle(rawValue: feedingStyleRaw) ?? .formula }

    private var profile: BabyProfile {
        BabyProfile(
            name: babyName,
            birthDate: birthInterval > 0 ? Date(timeIntervalSince1970: birthInterval) : nil,
            sex: BabySex(rawValue: sexRaw) ?? .unspecified,
            dueDate: dueInterval > 0 ? Date(timeIntervalSince1970: dueInterval) : nil
        )
    }

    var body: some View {
        let profile = profile
        let intake = CareCharts.intake(feeds: feeds, weights: weights, profile: profile, style: style,
                                       feedsPerDay: feedsPerDay, range: interval, calendar: calendar)
        let diaperDays = CareCharts.diapers(diapers, range: interval, calendar: calendar)
        let rhythm = CareCharts.rhythm(feeds, range: interval, calendar: calendar)
        let overview = CareCharts.overview(concerns: concerns, doses: doses, visits: visits,
                                           feedDays: intake, diaperDays: diaperDays, range: interval, now: now)
        let floorStart = CareCharts.wetFloorStart(birthDate: profile.birthDate, calendar: calendar)
        let showsFloor = !diaperDays.isEmpty && (floorStart.map { $0 < interval.end } ?? false)

        List {
            Section {
                modePicker
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Picker("Showing", selection: $rangeRaw) {
                    ForEach(ChartRange.allCases) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                }
            } footer: {
                Text([rangeNote, "Averages count full days, so today is left out until it's over."]
                    .compactMap { $0 }.joined(separator: " "))
            }

            Section {
                ChartRow(sentence: CareCharts.intakeSentence(intake, unit: unit, name: profile.displayName, range: range,
                                                             today: calendar.startOfDay(for: now))) {
                    if !intake.isEmpty {
                        FeedsChart(days: intake, unit: unit, interval: interval, calendar: calendar)
                    }
                }
            } header: {
                Text("Feeds")
            } footer: {
                if CareCharts.showsTarget(intake) {
                    Text("The dashed line is each day's target, from the weight known by then.")
                }
            }

            Section {
                ChartRow(sentence: CareCharts.diaperSentence(diaperDays, range: range,
                                                             today: calendar.startOfDay(for: now))) {
                    if !diaperDays.isEmpty {
                        DiapersChart(days: diaperDays, floorStart: showsFloor ? floorStart : nil,
                                     interval: interval, calendar: calendar)
                    }
                }
            } header: {
                Text("Diapers")
            } footer: {
                if showsFloor {
                    Text("The dashed line is the 6 wet diapers a day to expect after the first week (AAP). Only the changes that were logged are counted.")
                }
            }

            if !rhythm.isEmpty {
                Section {
                    ChartRow(sentence: CareCharts.rhythmSentence(feeds, range: interval, calendar: calendar)) {
                        RhythmChart(points: rhythm, interval: interval, calendar: calendar)
                    }
                } header: {
                    Text("When feeds happen")
                } footer: {
                    Text("One mark per feed, at the time it started. Midnight to 6 AM is shaded.")
                }
            }

            Section {
                ChartRow(sentence: CareCharts.overviewSentence(overview, range: range)) {
                    if !overview.isEmpty {
                        CareOverviewChart(overview: overview, interval: interval, now: now, calendar: calendar,
                                          selection: $selection)
                    }
                }
                if let day = selectedDay {
                    selectedDayRows(day)
                }
            } header: {
                Text("Care")
            } footer: {
                if !overview.isEmpty {
                    Text("Concerns are bars, medicine doses diamonds and doctor visits crosses. Tap a day to see what was logged.")
                }
            }

            Section {
                TrendsView(
                    groups: FeedStats.groupByDay(feeds, calendar: calendar),
                    unit: unit,
                    targetML: targetML,
                    calendar: calendar
                )
                .padding(.vertical, 8)
            } header: {
                Text("The numbers")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
    }

    /// Says where "since the last visit" starts, or that there isn't one yet.
    private var rangeNote: String? {
        guard ChartRange(rawValue: rangeRaw) == .sinceLastVisit else { return nil }
        guard let lastVisit else { return "No doctor visit logged yet, so this shows the last 2 weeks." }
        return "Since \(CareCharts.dayLabel(lastVisit, calendar: calendar)), the last doctor visit."
    }

    /// The same target the Today tab shows, via the shared helper, so the
    /// "% of target" in the numbers can't contradict the Daily target card.
    private var targetML: Double? {
        FeedingGuidance.currentTarget(weights: weights, profile: profile, style: style,
                                      feedsPerDay: feedsPerDay, calendar: calendar).target?.targetML
    }

    // MARK: The day picked in the care chart

    private var selectedDay: Date? {
        guard let selection else { return nil }
        let day = calendar.startOfDay(for: selection)
        return day >= interval.start && day <= now ? day : nil
    }

    @ViewBuilder
    private func selectedDayRows(_ day: Date) -> some View {
        let items = items(on: day)
        HStack {
            Text(FeedStats.dayTitle(for: day, calendar: calendar, now: now))
                .font(.headline)
            Spacer()
            Button {
                selection = nil
            } label: {
                Label("Close", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        if items.isEmpty {
            Text("Nothing logged that day.")
                .foregroundStyle(.secondary)
        }
        ForEach(items) { item in
            Button {
                router.sheet = .editEntry(item.ref)
            } label: {
                TimelineRow(item: item, unit: unit, weightUnit: weightUnit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The day's entries, exactly as the Timeline lists them.
    private func items(on day: Date) -> [TimelineItem] {
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let sources = TimelineSources(feeds: feeds, diapers: diapers, foods: foods, weights: weights, notes: notes,
                                      concerns: concerns, doses: doses, visits: visits)
        return TimelineBuilder.items(sources, babyID: babyID).filter { $0.date >= day && $0.date < end }
    }
}

/// The sentence that states the value, then the chart.
private struct ChartRow<Content: View>: View {
    let sentence: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(sentence)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .padding(.vertical, 6)
    }
}

// MARK: The charts

/// Bottle volume a day, with the target when bottles were the whole of it,
/// and feeds a day underneath. A baby fed only at the breast gets the feed
/// count alone: an empty volume chart would read as not eating.
private struct FeedsChart: View {
    let days: [CareCharts.IntakeDay]
    let unit: VolumeUnit
    let interval: DateInterval
    let calendar: Calendar

    private var showsVolume: Bool { CareCharts.showsVolume(days) }
    private var mixed: Bool { days.contains { $0.bottles > 0 } && days.contains { $0.nursing > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsVolume {
                volumeChart
            }
            countChart
        }
    }

    private var volumeChart: some View {
        let showsTarget = CareCharts.showsTarget(days)
        return Chart {
            ForEach(days) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Volume", unit.fromMilliliters(day.volumeML)))
                    .foregroundStyle(Color.accentColor.gradient)
            }
            if showsTarget {
                ForEach(days) { day in
                    if let target = day.targetML {
                        LineMark(x: .value("Day", day.day, unit: .day), y: .value("Target", unit.fromMilliliters(target)))
                            .interpolationMethod(.stepCenter)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartYAxisLabel(mixed ? "\(unit.symbol) from bottles" : unit.symbol)
        .frame(height: 170)
        .accessibilityChartDescriptor(ChartDescription(
            title: "Volume a day",
            summary: showsTarget ? "Bars are each day's volume; the dashed line is that day's target." : "Bars are each day's bottle volume.",
            xTitle: "Day", yTitle: unit.symbol,
            series: [.init(name: "Volume", points: days.map {
                .init(label: CareCharts.dayLabel($0.day, calendar: calendar), value: unit.fromMilliliters($0.volumeML))
            })]
        ))
    }

    private var countChart: some View {
        Chart {
            ForEach(days) { day in
                if mixed {
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Feeds", day.bottles))
                        .foregroundStyle(by: .value("Kind", "Bottle"))
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Feeds", day.nursing))
                        .foregroundStyle(by: .value("Kind", "Nursing"))
                } else {
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Feeds", day.feeds))
                        .foregroundStyle(showsVolume ? Color.accentColor.opacity(0.55) : FeedKind.nursing.color)
                }
            }
        }
        .chartForegroundStyleScale(["Bottle": Color.accentColor.opacity(0.55), "Nursing": FeedKind.nursing.color])
        .chartXScale(domain: interval.start...interval.end)
        .chartYAxisLabel("feeds")
        .frame(height: showsVolume ? 120 : 170)
        .accessibilityChartDescriptor(ChartDescription(
            title: "Feeds a day",
            summary: "One bar per day with feeds logged; a day with none is a gap.",
            xTitle: "Day", yTitle: "Feeds",
            series: [.init(name: "Feeds", points: days.map {
                .init(label: CareCharts.dayLabel($0.day, calendar: calendar), value: Double($0.feeds))
            })]
        ))
    }
}

/// Wet and dirty stacked a day, with the 6-wet line from the end of the
/// first week. A wet-and-dirty change counts once in each, as it does in
/// every tally.
private struct DiapersChart: View {
    let days: [CareCharts.DiaperDay]
    let floorStart: Date?
    let interval: DateInterval
    let calendar: Calendar

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Diapers", day.wet))
                    .foregroundStyle(by: .value("Kind", "Wet"))
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Diapers", day.dirty))
                    .foregroundStyle(by: .value("Kind", "Dirty"))
            }
            if let floorStart {
                RuleMark(xStart: .value("From", max(floorStart, interval.start)), xEnd: .value("To", interval.end),
                         y: .value("Wet a day", CareCharts.wetFloor))
                    // Not in the wet colour: it runs across the wet bars.
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
        }
        .chartYAxis {
            AxisMarks()
            // Named at the edge, outside the plot: a label on the line itself
            // sat on top of whichever bar was under it.
            if floorStart != nil {
                AxisMarks(position: .leading, values: [CareCharts.wetFloor]) { _ in
                    AxisValueLabel("6 wet")
                }
            }
        }
        .chartForegroundStyleScale(["Wet": DiaperKind.wet.color, "Dirty": DiaperKind.dirty.color])
        .chartXScale(domain: interval.start...interval.end)
        .frame(height: 180)
        .accessibilityChartDescriptor(ChartDescription(
            title: "Diapers a day",
            summary: "Wet and dirty diapers per day, for the days they were logged.",
            xTitle: "Day", yTitle: "Diapers",
            series: [
                .init(name: "Wet", points: days.map { .init(label: CareCharts.dayLabel($0.day, calendar: calendar), value: Double($0.wet)) }),
                .init(name: "Dirty", points: days.map { .init(label: CareCharts.dayLabel($0.day, calendar: calendar), value: Double($0.dirty)) }),
            ]
        ))
    }
}

/// A mark per feed: the day across, the time of day down, midnight at the
/// top as on a calendar. Kinds differ by shape as well as colour.
private struct RhythmChart: View {
    let points: [CareCharts.FeedPoint]
    let interval: DateInterval
    let calendar: Calendar

    private var kinds: [FeedKind] { FeedKind.allCases.filter { kind in points.contains { $0.kind == kind } } }

    private static func shape(_ kind: FeedKind) -> BasicChartSymbolShape {
        switch kind {
        case .formula: .circle
        case .breastMilk: .square
        case .nursing: .triangle
        }
    }

    var body: some View {
        Chart {
            // Hours are plotted below zero so the axis reads down the day.
            RectangleMark(xStart: .value("From", interval.start), xEnd: .value("To", interval.end),
                          yStart: .value("Night starts", 0), yEnd: .value("Night ends", -6))
                .foregroundStyle(Color.indigo.opacity(0.1))
            ForEach(points) { point in
                PointMark(x: .value("Day", point.day, unit: .day), y: .value("Time", -point.hour))
                    .symbol(by: .value("Kind", point.kind.title))
                    .foregroundStyle(by: .value("Kind", point.kind.title))
                    .symbolSize(28)
            }
        }
        .chartForegroundStyleScale(domain: kinds.map(\.title), range: kinds.map(\.color))
        .chartSymbolScale(domain: kinds.map(\.title), range: kinds.map { Self.shape($0) })
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: -24...0)
        .chartYAxis {
            AxisMarks(values: [0, -6, -12, -18, -24]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(Self.hourLabel(-hour))
                    }
                }
            }
        }
        .frame(height: 220)
        .accessibilityChartDescriptor(ChartDescription(
            title: "When feeds happen",
            summary: "One point per feed, by day and the time it started.",
            xTitle: "Feed", yTitle: "Time of day", yRange: 0...24, yText: Self.clockText,
            series: [.init(name: "Feeds", points: points.map {
                .init(label: "\(CareCharts.dayLabel($0.day, calendar: calendar)), \(Self.clockText($0.hour)), \($0.kind.title)",
                      value: $0.hour)
            })]
        ))
    }

    static func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0, 24: "12 AM"
        case 12: "Noon"
        case 1..<12: "\(hour) AM"
        default: "\(hour - 12) PM"
        }
    }

    /// "2:10 AM", from hours after midnight, already in the app's time zone.
    static func clockText(_ hour: Double) -> String {
        let minutes = Int((hour * 60).rounded())
        let h = (minutes / 60) % 24
        let m = minutes % 60
        let twelve = h % 12 == 0 ? 12 : h % 12
        return "\(twelve):\(m < 10 ? "0" : "")\(m) \(h < 12 ? "AM" : "PM")"
    }
}

/// Lanes by day: concerns as bars from start to finish (or today), doses as
/// diamonds, visits as crosses with a line down the chart, and a cell a day
/// for feeds and diapers that deepens with the count. Tapping picks a day.
private struct CareOverviewChart: View {
    let overview: CareCharts.Overview
    let interval: DateInterval
    let now: Date
    let calendar: Calendar
    @Binding var selection: Date?

    private static let lanes = ["Concerns", "Medicines", "Visits", "Feeds", "Diapers"]

    private var maxFeeds: Double { Double(max(1, overview.feedDays.map(\.feeds).max() ?? 1)) }
    private var maxDiapers: Double { Double(max(1, overview.diaperDays.map { $0.wet + $0.dirty }.max() ?? 1)) }

    private func dayEnd(_ day: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
    }

    var body: some View {
        Chart {
            ForEach(overview.concerns) { span in
                // At least a few hours wide, so an afternoon's worry still shows.
                BarMark(xStart: .value("Started", span.start),
                        xEnd: .value("Ended", max(span.end, span.start.addingTimeInterval(6 * 3600))),
                        y: .value("Lane", "Concerns"), height: .fixed(12))
                    .foregroundStyle(Color.orange.opacity(span.ongoing ? 0.9 : 0.45))
                    .cornerRadius(6)
            }
            ForEach(overview.doses) { dose in
                PointMark(x: .value("Given", dose.time), y: .value("Lane", "Medicines"))
                    .symbol(.diamond)
                    .symbolSize(40)
                    .foregroundStyle(Color.mint)
            }
            ForEach(overview.visits) { visit in
                RuleMark(x: .value("Visit", visit.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.indigo.opacity(0.5))
                PointMark(x: .value("Visit", visit.date), y: .value("Lane", "Visits"))
                    .symbol(.cross)
                    .symbolSize(60)
                    .foregroundStyle(Color.indigo)
            }
            ForEach(overview.feedDays) { day in
                RectangleMark(xStart: .value("Day", day.day.addingTimeInterval(3600)),
                              xEnd: .value("Day ends", dayEnd(day.day).addingTimeInterval(-3600)),
                              y: .value("Lane", "Feeds"), height: .fixed(12))
                    .foregroundStyle(Color.accentColor.opacity(0.25 + 0.75 * Double(day.feeds) / maxFeeds))
                    .cornerRadius(2)
            }
            ForEach(overview.diaperDays) { day in
                RectangleMark(xStart: .value("Day", day.day.addingTimeInterval(3600)),
                              xEnd: .value("Day ends", dayEnd(day.day).addingTimeInterval(-3600)),
                              y: .value("Lane", "Diapers"), height: .fixed(12))
                    .foregroundStyle(DiaperKind.wet.color.opacity(0.25 + 0.75 * Double(day.wet + day.dirty) / maxDiapers))
                    .cornerRadius(2)
            }
            if let selection {
                let day = calendar.startOfDay(for: selection)
                RectangleMark(xStart: .value("Selected", day), xEnd: .value("Selected ends", dayEnd(day)))
                    .foregroundStyle(Color.primary.opacity(0.08))
            }
        }
        .chartYScale(domain: Self.lanes)
        .chartXScale(domain: interval.start...interval.end)
        .chartXSelection(value: $selection)
        .chartGesture { proxy in
            // A tap, not the default drag: it picks a day and leaves it
            // picked, and doesn't fight the list's scrolling.
            SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
        }
        .frame(height: 210)
        .accessibilityChartDescriptor(description)
    }

    private var description: ChartDescription {
        var days: [Date] = []
        var day = interval.start
        while day < interval.end, day <= now {
            days.append(day)
            day = dayEnd(day)
        }
        func count(_ dates: [Date]) -> [ChartDescription.Point] {
            let counts = Dictionary(grouping: dates) { calendar.startOfDay(for: $0) }.mapValues(\.count)
            return days.map { .init(label: CareCharts.dayLabel($0, calendar: calendar), value: Double(counts[$0] ?? 0)) }
        }
        let feeds = Dictionary(uniqueKeysWithValues: overview.feedDays.map { ($0.day, $0.feeds) })
        let diapers = Dictionary(uniqueKeysWithValues: overview.diaperDays.map { ($0.day, $0.wet + $0.dirty) })
        let concerns = overview.concerns.map { span in
            "\(span.title), \(CareCharts.dayLabel(span.start, calendar: calendar)) to "
                + (span.ongoing ? "now, ongoing" : CareCharts.dayLabel(span.end, calendar: calendar))
        }
        return ChartDescription(
            title: "Care by day",
            summary: concerns.isEmpty ? "No concerns in this stretch." : "Concerns: " + concerns.joined(separator: "; ") + ".",
            xTitle: "Day", yTitle: "Count",
            series: [
                .init(name: "Feeds", points: days.map { .init(label: CareCharts.dayLabel($0, calendar: calendar), value: Double(feeds[$0] ?? 0)) }),
                .init(name: "Diapers", points: days.map { .init(label: CareCharts.dayLabel($0, calendar: calendar), value: Double(diapers[$0] ?? 0)) }),
                .init(name: "Medicine doses", points: count(overview.doses.map(\.time))),
                .init(name: "Doctor visits", points: count(overview.visits.map(\.date))),
            ]
        )
    }
}

/// The weight chart on the Baby tab: the weigh-ins, and, once sex is known,
/// the WHO 3rd–97th and 15th–85th percentile bands with the median, a dashed
/// line from the last weigh-in to today along its percentile, and a birth
/// weight line for as long as "back to birth weight" is the question.
struct WeightChartView: View {
    let chart: CareCharts.WeightChart
    let weightUnit: WeightUnit
    let calendar: Calendar

    private var axisTitle: String { weightUnit == .kilograms ? "kg" : "lb" }

    private func value(_ grams: Double) -> Double {
        weightUnit == .kilograms ? grams / 1000 : grams / WeightUnit.gramsPerPound
    }

    var body: some View {
        Chart {
            ForEach(chart.outer) { band in
                AreaMark(x: .value("Date", band.date), yStart: .value("3rd", value(band.low)),
                         yEnd: .value("97th", value(band.high)), series: .value("Band", "3rd–97th"))
                    .foregroundStyle(Color.blue.opacity(0.08))
            }
            ForEach(chart.inner) { band in
                AreaMark(x: .value("Date", band.date), yStart: .value("15th", value(band.low)),
                         yEnd: .value("85th", value(band.high)), series: .value("Band", "15th–85th"))
                    .foregroundStyle(Color.blue.opacity(0.12))
            }
            ForEach(chart.median) { point in
                LineMark(x: .value("Date", point.date), y: .value("Weight", value(point.grams)),
                         series: .value("Series", "50th"))
                    .foregroundStyle(Color.blue.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            if let birth = chart.birthGrams {
                RuleMark(y: .value("Birth weight", value(birth)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .foregroundStyle(Color.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("Birth weight").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            ForEach(chart.weighIns) { point in
                LineMark(x: .value("Date", point.date), y: .value("Weight", value(point.grams)),
                         series: .value("Series", "Weighed"))
                    .foregroundStyle(Color.blue)
                PointMark(x: .value("Date", point.date), y: .value("Weight", value(point.grams)))
                    .foregroundStyle(Color.blue)
            }
            ForEach(chart.projection) { point in
                LineMark(x: .value("Date", point.date), y: .value("Weight", value(point.grams)),
                         series: .value("Series", "Estimated"))
                    .foregroundStyle(Color.blue.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .chartXScale(domain: chart.domain ?? Date.now...Date.now)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel(axisTitle)
        .frame(height: 210)
        .accessibilityChartDescriptor(ChartDescription(
            title: "Weight",
            summary: chart.outer.isEmpty ? "The weigh-ins over time."
                : "The weigh-ins against the WHO 3rd to 97th and 15th to 85th percentile bands.",
            xTitle: "Date", yTitle: axisTitle,
            series: [.init(name: "Weigh-ins", points: chart.weighIns.map {
                .init(label: CareCharts.dayLabel($0.date, calendar: calendar), value: value($0.grams))
            })]
        ))
    }

    /// What the chart's lines are, for the row's caption. Nil when it's only
    /// the weigh-ins, which need no key.
    var caption: String? {
        var parts: [String] = []
        if !chart.outer.isEmpty { parts.append("Shaded: the WHO 15th–85th and 3rd–97th percentiles, with the 50th as a line.") }
        if !chart.projection.isEmpty { parts.append("Dashed: an estimate from the last weigh-in to today.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

// MARK: VoiceOver

/// What VoiceOver's audio graph reads for a chart: its series, one value per
/// label, instead of the marks it would otherwise guess from.
private struct ChartDescription: AXChartDescriptorRepresentable {
    struct Point {
        let label: String
        let value: Double
    }

    struct Series {
        let name: String
        let points: [Point]
    }

    let title: String
    let summary: String
    let xTitle: String
    let yTitle: String
    var yRange: ClosedRange<Double>?
    var yText: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1))) }
    let series: [Series]

    func makeChartDescriptor() -> AXChartDescriptor {
        var labels: [String] = []
        var seen: Set<String> = []
        for point in series.flatMap(\.points) where seen.insert(point.label).inserted {
            labels.append(point.label)
        }
        let top = max(1, series.flatMap(\.points).map(\.value).max() ?? 1)
        let x = AXCategoricalDataAxisDescriptor(title: xTitle, categoryOrder: labels)
        let y = AXNumericDataAxisDescriptor(title: yTitle, range: yRange ?? 0...top, gridlinePositions: [], valueDescriptionProvider: yText)
        return AXChartDescriptor(
            title: title,
            summary: summary,
            xAxis: x,
            yAxis: y,
            additionalAxes: [],
            series: series.map { series in
                AXDataSeriesDescriptor(name: series.name, isContinuous: false,
                                       dataPoints: series.points.map { AXDataPoint(x: $0.label, y: $0.value) })
            }
        )
    }
}
