import SwiftData
import SwiftUI

/// What a tap on the Live Activity opens: a feed and a diaper as the two big
/// buttons, since they're nearly always why someone tapped, and everything
/// else from "+" in a short list underneath.
struct QuickLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0

    var body: some View {
        NavigationStack {
            List {
                if let session = NursingTimer.shared.session {
                    Section {
                        Button {
                            // The timer's Switch and Done live on Today.
                            router.tab = .today
                            dismiss()
                        } label: {
                            Label("Nursing · \(session.side.title) – go to the timer", systemImage: "timer")
                                .foregroundStyle(FeedKind.nursing.color)
                        }
                    }
                }

                Section {
                    HStack(spacing: 12) {
                        bigButton("Feed", systemImage: lastFeedKind.systemImage, tint: lastFeedKind.color) {
                            router.sheet = .log(lastFeedKind)
                        }
                        bigButton("Diaper", systemImage: DiaperKind.wet.systemImage, tint: DiaperKind.wet.color) {
                            router.sheet = .logDiaper(.wet)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Something else") {
                    ForEach(AddEntryKind.available(birthInterval: birthInterval, calendar: calendar)) { kind in
                        Button {
                            router.sheet = .newEntry(kind)
                        } label: {
                            Label {
                                Text(kind.title).foregroundStyle(Color.primary)
                            } icon: {
                                Image(systemName: kind.systemImage).foregroundStyle(kind.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The feed sheet opens on the kind fed last, the likeliest next one; its
    /// picker switches it in one tap.
    private var lastFeedKind: FeedKind {
        let babyID = AppSettings.currentBabyID
        var descriptor = FetchDescriptor<FeedEntry>(
            predicate: #Predicate { $0.babyID == babyID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.kind ?? .formula
    }

    private func bigButton(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 34))
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log a \(title.lowercased())")
    }
}

#Preview {
    QuickLogSheet()
        .environment(AppRouter())
        .modelContainer(.preview)
}
