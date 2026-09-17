import SwiftUI

struct FeedRow: View {
    let entry: FeedEntry
    let unit: VolumeUnit

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
                if !entry.note.isEmpty {
                    Text(entry.note)
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
