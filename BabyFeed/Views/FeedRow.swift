import SwiftUI

struct FeedRow: View {
    let entry: FeedEntry
    let unit: VolumeUnit

    private var subtitle: String {
        var parts: [String] = []
        if !entry.loggedByName.isEmpty { parts.append("Logged by \(entry.loggedByName)") }
        if !entry.note.isEmpty { parts.append(entry.note) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind.systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(entry.kind.color, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.kind.title)
                    .font(.headline)
                // "Logged by", never "fed by": the person who tapped Save
                // isn't necessarily the person who held the bottle. The
                // attribution comes first so truncation eats the note instead.
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.detailText(unit: unit))
                    .font(.headline)
                    .monospacedDigit()
                Text(entry.startTime.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
