import SwiftUI

/// One row of the timeline, whatever kind of entry it is.
struct TimelineRow: View {
    let item: TimelineItem
    let unit: VolumeUnit
    let weightUnit: WeightUnit
    /// Off in the Timeline, where each row sits under its day; on in lists
    /// that aren't grouped by day, so last night's feed reads "yesterday,
    /// 11:40 PM" rather than a bare time.
    var showsDay = false

    @Environment(\.timeZone) private var timeZone
    @Environment(\.calendar) private var calendar

    private func when(_ date: Date) -> String {
        showsDay ? ClockText.since(date, now: .now, in: timeZone) : ClockText.time(date, in: timeZone)
    }

    var body: some View {
        switch item {
        case .feed(let feed):
            FeedRow(entry: feed, unit: unit, showsDay: showsDay)
        case .diaper(let diaper):
            EntryRow(
                symbol: item.systemImage,
                tint: item.tint,
                title: diaper.kind.entryTitle,
                subtitle: EntryRow.joined([LoggedBy.text(diaper.loggedByName), diaper.note]),
                value: nil,
                time: when(diaper.time),
                compact: true
            )
        case .food(let food, let isFirstTime):
            EntryRow(
                symbol: item.systemImage,
                tint: item.tint,
                title: food.name,
                badge: isFirstTime ? "First time" : nil,
                subtitle: EntryRow.joined([food.texture.title, food.reaction.title, LoggedBy.text(food.loggedByName), food.note]),
                value: nil,
                time: when(food.time)
            )
        case .weight(let weight):
            EntryRow(
                symbol: item.systemImage,
                tint: item.tint,
                title: "Weight",
                subtitle: EntryRow.joined([LoggedBy.text(weight.loggedByName), weight.note]),
                value: weightUnit.format(grams: weight.grams),
                // A weigh-in has a day, not a time of day.
                time: showsDay && !calendar.isDateInToday(weight.date)
                    ? weight.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: timeZone))
                    : nil
            )
        case .note(let note):
            EntryRow(
                symbol: item.systemImage,
                tint: item.tint,
                title: note.kind.title,
                badge: note.severity?.title,
                subtitle: EntryRow.joined([note.note, LoggedBy.text(note.loggedByName)]),
                value: nil,
                time: when(note.date),
                subtitleLines: 3
            )
        case .concern(let concern):
            EntryRow(
                symbol: item.systemImage,
                tint: item.tint,
                title: concern.title.isEmpty ? concern.kind.title : concern.title,
                badge: concern.isOngoing ? "Ongoing" : nil,
                // The badge already says it's ongoing; the subtitle only
                // needs the day, not "ongoing · day 4" beside it.
                subtitle: EntryRow.joined([concern.isOngoing
                                               ? "day \(ConcernStats.dayNumber(concern, now: .now, calendar: calendar))"
                                               : ConcernStats.statusText(concern, now: .now, calendar: calendar),
                                           concern.note, LoggedBy.text(concern.loggedByName)]),
                value: nil,
                time: when(concern.startedAt),
                subtitleLines: 2
            )
        case .dose(let dose):
            EntryRow(
                symbol: item.systemImage,
                tint: item.tint,
                title: dose.medicationName,
                subtitle: EntryRow.joined([LoggedBy.text(dose.loggedByName), dose.note]),
                value: dose.amountText,
                time: when(dose.time)
            )
        case .visit(let visit):
            EntryRow(
                symbol: item.systemImage,
                tint: item.tint,
                title: visit.kind.title,
                subtitle: EntryRow.joined([visit.provider, visit.reason, visit.doctorNotes,
                                           LoggedBy.text(visit.loggedByName)]),
                value: nil,
                time: when(visit.date),
                // Three, like notes: the doctor's words fill two, and "Logged
                // by" comes after them.
                subtitleLines: 3
            )
        }
    }
}

/// Icon, title and subtitle on the left, value and time on the right: one
/// layout for every kind of entry, feeds included. At accessibility text sizes
/// it stacks into one column rather than squeezing the title into "Formu-la"
/// and cutting the attribution down to "Logge…".
struct EntryRow: View {
    let symbol: String
    let tint: Color
    let title: String
    var badge: String? = nil
    let subtitle: String
    let value: String?
    let time: String?
    /// Diapers are the most frequent thing logged; a smaller icon keeps a day
    /// of them from dominating the list.
    var compact = false
    var subtitleLines = 1

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The parts that were given, in order, with " · " between them.
    static func joined(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "7 feeds · 20 oz · 3 dirty" that wraps only after a dot, so a line
    /// never ends on "3" with "dirty" on the next.
    static func wrappingAtDots(_ text: String) -> String {
        text.components(separatedBy: " · ")
            .map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
            .joined(separator: "\u{00A0}· ")
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                sideBySide
            }
        }
        .padding(.vertical, compact ? 1 : 4)
        .accessibilityElement(children: .combine)
    }

    private var sideBySide: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                titleText
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(subtitleLines)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let value {
                    Text(value)
                        .font(.headline)
                        .monospacedDigit()
                }
                if let time {
                    Text(time)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    /// One column, full width, nothing truncated, including who logged it.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                icon
                titleText
            }
            let trailing = EntryRow.joined([value, time])
            if !trailing.isEmpty {
                Text(trailing)
                    .font(.headline)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var icon: some View {
        Image(systemName: symbol)
            .font(compact ? .subheadline : .headline)
            .foregroundStyle(.white)
            .frame(width: compact ? 28 : 40, height: compact ? 28 : 40)
            .background(tint, in: Circle())
            .frame(width: 40)
    }

    private var titleText: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(compact ? .body : .headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(tint)
            }
        }
    }
}
