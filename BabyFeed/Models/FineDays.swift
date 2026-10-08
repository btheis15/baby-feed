import Foundation

/// Days with nothing logged that a parent marked "everything was fine".
///
/// Nobody logs every day, and a day with nothing in it is a gap in the
/// record, never a zero. Marking it fine lets the charts fill it in with an
/// estimate from the days around it, drawn faded and tagged "est." so it can't
/// be mistaken for what was logged. Averages still count only the days that
/// were logged, so the numbers a doctor sees stay the real ones.
///
/// A mark is a `CareNote` of kind `allFine` at noon that day, so it syncs to
/// the other phone like any note, and the Timeline and the doctor's summary
/// show it for what it is.
enum FineDays {
    static let noteText = "Nothing was logged this day. Marked as a day when everything was fine."

    /// How far either side of a fine day to look for days to estimate from.
    static let neighbourWindowDays = 7
    /// At most this many of the nearest logged days go into an estimate.
    static let neighbourCount = 6

    /// The days marked fine, as start-of-day dates.
    static func marked(_ notes: [CareNote], calendar: Calendar) -> Set<Date> {
        Set(notes.active(for: nil).filter { $0.kind == .allFine }.map { calendar.startOfDay(for: $0.date) })
    }

    /// The note that marks `day` fine, if there is one.
    static func mark(on day: Date, in notes: [CareNote], calendar: Calendar) -> CareNote? {
        notes.active(for: nil).first { $0.kind == .allFine && calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// The new mark for `day`: noon, so a time-zone change can't push it into
    /// the day either side.
    static func newMark(on day: Date, babyID: UUID?, loggedByName: String, calendar: Calendar) -> CareNote {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        return CareNote(babyID: babyID, date: noon, kind: .allFine, note: noteText, loggedByName: loggedByName)
    }

    /// Whole days from `start` up to, not including, `today` with no feed and
    /// no diaper logged: today isn't over, so it isn't missing yet. Newest
    /// first.
    static func unlogged(feeds: [FeedEntry], diapers: [DiaperEntry], from start: Date, today: Date,
                         calendar: Calendar) -> [Date] {
        let logged = Set(feeds.active(for: nil).map { calendar.startOfDay(for: $0.startTime) })
            .union(diapers.active(for: nil).map { calendar.startOfDay(for: $0.time) })
        var days: [Date] = []
        var day = calendar.startOfDay(for: start)
        let end = calendar.startOfDay(for: today)
        while day < end {
            if !logged.contains(day) { days.append(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days.reversed()
    }

    /// The logged days nearest `day`, closest first, within the window.
    private static func neighbours<Day>(of day: Date, in days: [Day], date: (Day) -> Date) -> [Day] {
        days
            .map { (day: $0, distance: abs(date($0).timeIntervalSince(day))) }
            .filter { $0.distance > 0 && $0.distance <= Double(neighbourWindowDays) * 86_400 + 3_600 }
            .sorted { $0.distance < $1.distance }
            .prefix(neighbourCount)
            .map(\.day)
    }

    private static func mean(_ values: [Int]) -> Int {
        values.isEmpty ? 0 : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    /// The logged days with an estimate added for each fine day that has no
    /// feeds, in day order. A fine day with no logged days near it stays a
    /// gap: there's nothing honest to estimate from.
    static func filled(_ days: [CareCharts.IntakeDay], fine: Set<Date>) -> [CareCharts.IntakeDay] {
        let logged = days.filter { !$0.isEstimated }
        let loggedDays = Set(logged.map(\.day))
        let estimates = fine.subtracting(loggedDays).compactMap { day -> CareCharts.IntakeDay? in
            let near = neighbours(of: day, in: logged, date: \.day)
            guard !near.isEmpty else { return nil }
            return CareCharts.IntakeDay(
                day: day,
                feeds: mean(near.map(\.feeds)),
                bottles: mean(near.map(\.bottles)),
                nursing: mean(near.map(\.nursing)),
                volumeML: near.map(\.volumeML).reduce(0, +) / Double(near.count),
                nursingMinutes: mean(near.map(\.nursingMinutes)),
                targetML: near.first?.targetML,
                isEstimated: true
            )
        }
        return (logged + estimates).sorted { $0.day < $1.day }
    }

    /// The same for diapers.
    static func filled(_ days: [CareCharts.DiaperDay], fine: Set<Date>) -> [CareCharts.DiaperDay] {
        let logged = days.filter { !$0.isEstimated }
        let loggedDays = Set(logged.map(\.day))
        let estimates = fine.subtracting(loggedDays).compactMap { day -> CareCharts.DiaperDay? in
            let near = neighbours(of: day, in: logged, date: \.day)
            guard !near.isEmpty else { return nil }
            return CareCharts.DiaperDay(day: day, wet: mean(near.map(\.wet)), dirty: mean(near.map(\.dirty)),
                                        isEstimated: true)
        }
        return (logged + estimates).sorted { $0.day < $1.day }
    }

    /// " 2 days marked fine are estimated from the days around them, and left
    /// out of the average." Empty with no estimates, so it appends to any
    /// chart's sentence.
    static func sentenceSuffix(estimatedDays: Int) -> String {
        switch estimatedDays {
        case 0: ""
        case 1: " 1 day marked fine is estimated from the days around it, and left out of the average."
        default: " \(estimatedDays) days marked fine are estimated from the days around them, and left out of the average."
        }
    }
}
