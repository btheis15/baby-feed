import SwiftData
import SwiftUI

/// "For the pediatrician": the recent numbers laid out to be read across a
/// desk, and shareable as plain text.
///
/// The table and the shared text both come from one `DaySummaryGenerator.Report`
/// so they can't disagree.
struct SummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    /// So the summary groups days the same way History does, including a
    /// pinned time zone.
    @Environment(\.calendar) private var calendar
    /// Four columns stop fitting at accessibility sizes; see dayTableSection.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \FeedEntry.startTime, order: .reverse) private var entries: [FeedEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query(sort: \CareNote.date, order: .reverse) private var careNotes: [CareNote]

    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    @State private var days = 7
    @State private var friendly: String?
    @State private var isGenerating = false

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces }

    private var report: DaySummaryGenerator.Report {
        DaySummaryGenerator.report(
            entries: entries.active(for: UUID(uuidString: currentBabyIDRaw)),
            weights: weights.active(for: UUID(uuidString: currentBabyIDRaw)),
            careNotes: careNotes.active(for: UUID(uuidString: currentBabyIDRaw)),
            days: days,
            unit: unit,
            weightUnit: weightUnit,
            profile: BabyProfile.load(),
            calendar: calendar
        )
    }

    var body: some View {
        NavigationStack {
            // Built once here and passed down: it filters and regroups the
            // whole log, and reading it as a computed property meant doing that
            // five times per render.
            let report = report
            let facts = DaySummaryGenerator.plainText(from: report)

            List {
                windowSection(report)

                if !report.weightItems.isEmpty {
                    itemSection("Weight", items: report.weightItems)
                }
                if report.hasFeeds {
                    itemSection("Per day", items: report.averageItems, footer: "Averaged over the \(report.days.count) day\(report.days.count == 1 ? "" : "s") with feeds logged.")
                    itemSection("Totals", items: report.totalItems)
                    dayTableSection(report.days)
                } else {
                    Section {
                        Text("No feeds logged in this period.")
                            .foregroundStyle(.secondary)
                    }
                }

                if report.hasNotes {
                    notesSection(report.notes)
                }

                if let friendly {
                    Section("In plain English") {
                        Text(friendly)
                            .textSelection(.enabled)
                    }
                }
                rewriteSection(facts: facts)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("For the pediatrician")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: friendly ?? facts, subject: Text("Feeding summary")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .onChange(of: days) { _, _ in friendly = nil }
        }
    }

    // MARK: Sections

    private func windowSection(_ report: DaySummaryGenerator.Report) -> some View {
        Section {
            Picker("Days", selection: $days) {
                Text("3 days").tag(3)
                Text("7 days").tag(7)
                Text("14 days").tag(14)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            LabeledContent("Baby", value: report.babyName)
            if let age = report.ageText {
                LabeledContent("Age", value: age)
            }
            LabeledContent("Period", value: report.windowText)
        }
    }

    private func itemSection(
        _ title: String,
        items: [DaySummaryGenerator.Report.Item],
        footer: String? = nil
    ) -> some View {
        Section {
            ForEach(items) { item in
                LabeledContent(item.label) {
                    Text(item.value)
                        .monospacedDigit()
                }
            }
        } header: {
            Text(title)
        } footer: {
            if let footer { Text(footer) }
        }
    }

    /// The day-by-day figures.
    ///
    /// Four columns only work at ordinary text sizes – at accessibility sizes
    /// they truncate to "Yest…" and "16.9…", so past that point each day
    /// becomes its own stacked row instead. Same numbers either way.
    @ViewBuilder
    private func dayTableSection(_ days: [DaySummaryGenerator.Report.Day]) -> some View {
        Section {
            if dynamicTypeSize.isAccessibilitySize {
                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.shortTitle)
                            .font(.subheadline.weight(.medium))
                        Text(stackedDetail(for: day))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                dayGrid(days)
            }
        } header: {
            Text("Day by day")
        }
    }

    /// "5 feeds · 16.9 oz · 17 min nursing"
    private func stackedDetail(for day: DaySummaryGenerator.Report.Day) -> String {
        var parts = ["\(day.feedCount) feed\(day.feedCount == 1 ? "" : "s")"]
        if let volume = day.volumeText { parts.append(volume) }
        if let nursing = day.nursingText { parts.append("\(nursing) nursing") }
        return parts.joined(separator: " · ")
    }

    private func dayGrid(_ days: [DaySummaryGenerator.Report.Day]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                // The day column absorbs the slack so the numbers sit at the
                // right edge instead of the table hugging the left.
                Text("Day")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Feeds").gridColumnAlignment(.trailing)
                Text("Bottle").gridColumnAlignment(.trailing)
                Text("Nursing").gridColumnAlignment(.trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Divider()
                .gridCellColumns(4)

            ForEach(days) { day in
                GridRow {
                    Text(day.shortTitle)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(day.feedCount)")
                        .monospacedDigit()
                    Text(day.volumeText ?? "–")
                        .monospacedDigit()
                        .foregroundStyle(day.volumeText == nil ? .secondary : .primary)
                    Text(day.nursingText ?? "–")
                        .monospacedDigit()
                        .foregroundStyle(day.nursingText == nil ? .secondary : .primary)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
    }

    /// The notes, which are the part a doctor reads rather than scans.
    private func notesSection(_ notes: [DaySummaryGenerator.Report.Note]) -> some View {
        Section {
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(note.kindTitle)
                            .font(.subheadline.weight(.medium))
                        if let severity = note.severityTitle {
                            Text(severity)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(note.author.isEmpty ? note.dateText : "\(note.dateText) · \(note.author)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(note.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Notes")
        } footer: {
            Text("Anything logged outside feeds in this period.")
        }
    }

    @ViewBuilder
    private func rewriteSection(facts: String) -> some View {
        if DaySummaryGenerator.canRewrite {
            Section {
                Button {
                    rewrite(facts: facts)
                } label: {
                    if isGenerating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(
                            friendly == nil ? "Rewrite in plain English" : "Rewrite again",
                            systemImage: "sparkles"
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isGenerating)
            } footer: {
                Text("Uses Apple Intelligence on this iPhone. Nothing leaves the device. Share sends whichever version is showing.")
            }
        }
    }

    private func rewrite(facts: String) {
        isGenerating = true
        Task {
            friendly = await DaySummaryGenerator.friendlySummary(from: facts)
            isGenerating = false
        }
    }
}

#Preview {
    SummarySheet()
        .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self], inMemory: true)
}
