import SwiftUI

struct FeedRow: View {
    let entry: FeedEntry
    let unit: VolumeUnit
    /// "yesterday, 11:40 PM" rather than a bare time, for lists that aren't
    /// grouped by day.
    var showsDay = false

    @Environment(\.timeZone) private var timeZone

    var body: some View {
        EntryRow(
            symbol: entry.kind.systemImage,
            tint: entry.kind.color,
            title: entry.kind.title,
            // "Logged by", never "fed by": the person who tapped Save isn't
            // necessarily the person who held the bottle. The attribution comes
            // first so any truncation eats the note instead.
            subtitle: EntryRow.joined([LoggedBy.text(entry.loggedByName), entry.note]),
            value: entry.detailText(unit: unit),
            time: showsDay
                ? ClockText.since(entry.startTime, now: .now, in: timeZone)
                : ClockText.time(entry.startTime, in: timeZone)
        )
    }
}
