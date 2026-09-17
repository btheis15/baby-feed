import SwiftData
import SwiftUI

/// "For the pediatrician": a plain-text recap of recent days you can share.
/// Optionally rewritten on-device by Apple Intelligence.
struct SummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FeedEntry.startTime, order: .reverse) private var entries: [FeedEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    @State private var days = 7
    @State private var friendly: String?
    @State private var isGenerating = false

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces }

    private var facts: String {
        DaySummaryGenerator.factualSummary(
            entries: entries.active(for: UUID(uuidString: currentBabyIDRaw)),
            weights: weights.active(for: UUID(uuidString: currentBabyIDRaw)),
            days: days,
            unit: unit,
            weightUnit: weightUnit,
            profile: BabyProfile.load()
        )
    }

    private var shareText: String { friendly ?? facts }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Days", selection: $days) {
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                    }
                    .pickerStyle(.segmented)

                    if let friendly {
                        summaryBlock(title: "Summary", text: friendly)
                    }
                    summaryBlock(title: friendly == nil ? "Summary" : "The numbers", text: facts)

                    if DaySummaryGenerator.canRewrite {
                        Button {
                            rewrite()
                        } label: {
                            if isGenerating {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label(friendly == nil ? "Rewrite in plain English" : "Rewrite again", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .disabled(isGenerating)

                        Text("Uses Apple Intelligence on this iPhone. Nothing leaves the device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("For the pediatrician")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareText, subject: Text("Feeding summary")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .onChange(of: days) { _, _ in friendly = nil }
        }
    }

    private func summaryBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func rewrite() {
        let input = facts
        isGenerating = true
        Task {
            friendly = await DaySummaryGenerator.friendlySummary(from: input)
            isGenerating = false
        }
    }
}

#Preview {
    SummarySheet()
        .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self], inMemory: true)
}
