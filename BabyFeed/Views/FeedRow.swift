import SwiftUI

struct FeedRow: View {
    let entry: FeedEntry
    let unit: VolumeUnit
    /// Two side-by-side columns stop fitting well before the largest sizes,
    /// where they squeeze the title into "Formu-la" and cut the attribution
    /// down to "Logge…". Above this the row stacks instead.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// "Logged by", never "fed by": the person who tapped Save isn't
    /// necessarily the person who held the bottle. The attribution comes
    /// first so any truncation eats the note instead.
    private var subtitle: String {
        var parts: [String] = []
        if !entry.loggedByName.isEmpty { parts.append("Logged by \(entry.loggedByName)") }
        if !entry.note.isEmpty { parts.append(entry.note) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedLayout
            } else {
                sideBySideLayout
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        Image(systemName: entry.kind.systemImage)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(entry.kind.color, in: Circle())
    }

    private var sideBySideLayout: some View {
        HStack(spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.kind.title)
                    .font(.headline)
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
    }

    /// One column, full width, nothing truncated – including who logged it.
    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                icon
                Text(entry.kind.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("\(entry.detailText(unit: unit)) · \(entry.startTime.formatted(date: .omitted, time: .shortened))")
                .font(.headline)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
