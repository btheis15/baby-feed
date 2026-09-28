import SwiftData
import SwiftUI

/// "For the pediatrician": the recent numbers laid out to be read across a
/// desk, and shareable as plain text.
///
/// The table and the shared text both come from one `DaySummaryGenerator.Report`
/// so they can't disagree.
struct SummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    /// So the summary groups days the same way the Timeline does, including a
    /// pinned time zone.
    @Environment(\.calendar) private var calendar
    /// The columns stop fitting at accessibility sizes; see dayTableSection.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \FeedEntry.startTime, order: .reverse) private var entries: [FeedEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query(sort: \CareNote.date, order: .reverse) private var careNotes: [CareNote]
    @Query(sort: \DiaperEntry.time, order: .reverse) private var diapers: [DiaperEntry]
    @Query(sort: \SolidFoodEntry.time, order: .reverse) private var solidFoods: [SolidFoodEntry]
    @Query(sort: \HealthConcern.startedAt, order: .reverse) private var concerns: [HealthConcern]
    @Query(sort: \MedicationDose.time, order: .reverse) private var doses: [MedicationDose]
    @Query(sort: \DoctorVisit.date, order: .reverse) private var visits: [DoctorVisit]

    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    /// Nil until a window is picked: then it's since the last visit.
    @State private var chosenWindow: ReportWindow?
    @State private var friendly: String?
    @State private var isGenerating = false

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces }

    private var babyID: UUID? { UUID(uuidString: currentBabyIDRaw) }

    /// Since the last visit, by default: what's happened since the doctor
    /// last saw the baby is what the doctor wants to hear.
    private var defaultWindow: ReportWindow {
        ReportWindow.defaultWindow(visits: visits.active(for: babyID), now: .now, calendar: calendar)
    }

    private var window: ReportWindow { chosenWindow ?? defaultWindow }

    private var windowChoices: [ReportWindow] {
        var choices: [ReportWindow] = []
        if case .since = defaultWindow { choices.append(defaultWindow) }
        choices += [.days(3), .days(7), .days(14), .days(30)]
        return choices
    }

    private var report: DaySummaryGenerator.Report {
        DaySummaryGenerator.report(
            entries: entries.active(for: babyID),
            weights: weights.active(for: babyID),
            careNotes: careNotes.active(for: babyID),
            diapers: diapers.active(for: babyID),
            solidFoods: solidFoods.active(for: babyID),
            concerns: concerns.active(for: babyID),
            doses: doses.active(for: babyID),
            visits: visits.active(for: babyID),
            window: window,
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
                if !report.hasFeeds {
                    Section {
                        Text("No feeds logged in this period.")
                            .foregroundStyle(.secondary)
                    }
                }
                if !report.averageItems.isEmpty {
                    itemSection("Per day", items: report.averageItems, footer: report.averagesFootnote)
                }
                if !report.totalItems.isEmpty {
                    itemSection("Totals", items: report.totalItems)
                }
                if !report.days.isEmpty {
                    dayTableSection(report.days, byWeek: report.byWeek)
                }

                if report.hasHealth {
                    healthSections(report)
                }

                if report.hasFoods {
                    foodsSection(report.foods)
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
            .onChange(of: chosenWindow) { _, _ in friendly = nil }
        }
    }

    // MARK: Sections

    private func windowSection(_ report: DaySummaryGenerator.Report) -> some View {
        Section {
            Picker("Period", selection: Binding(get: { window }, set: { chosenWindow = $0 })) {
                ForEach(windowChoices, id: \.self) { choice in
                    Text(choiceTitle(choice)).tag(choice)
                }
            }

            LabeledContent("Baby", value: report.babyName)
            if let age = report.ageText {
                LabeledContent("Age", value: age)
            }
            LabeledContent("Period", value: report.windowText)
        }
    }

    private func choiceTitle(_ choice: ReportWindow) -> String {
        switch choice {
        case .days(let days): "Last \(days) days"
        case .since: "Since the last visit"
        }
    }

    /// Follow-up, concerns and medicines: after "how's feeding going?",
    /// what the doctor asks about.
    @ViewBuilder
    private func healthSections(_ report: DaySummaryGenerator.Report) -> some View {
        if let followUp = report.followUp {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text(followUp.visitText).font(.subheadline.weight(.medium))
                    Text([followUp.note, followUp.dueText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Follow-up from the last visit")
            }
        }
        if !report.concerns.isEmpty {
            Section("Concerns") {
                ForEach(report.concerns) { concern in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(concern.title).font(.subheadline.weight(.medium))
                        Text("\(concern.startedText) · \(concern.statusText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(concern.updates, id: \.self) { update in
                            Text(update).font(.footnote)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        if !report.medicines.isEmpty {
            Section("Medicines given") {
                ForEach(report.medicines) { medicine in
                    LabeledContent {
                        Text(medicine.count == 1 ? medicine.lastText : "\(medicine.count)× · last \(medicine.lastText)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(medicine.name)
                    }
                }
            }
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
    /// The columns only work at ordinary text sizes – at accessibility sizes
    /// they truncate to "Yest…" and "16.9…", so past that point each day
    /// becomes its own stacked row instead. Same numbers either way.
    @ViewBuilder
    private func dayTableSection(_ days: [DaySummaryGenerator.Report.Day], byWeek: Bool) -> some View {
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
            Text(byWeek ? "Week by week" : "Day by day")
        }
    }

    /// "5 feeds · 16.9 oz · 17 min nursing · diapers 4 wet · 2 dirty"
    private func stackedDetail(for day: DaySummaryGenerator.Report.Day) -> String {
        DaySummaryGenerator.dayDetail(day)
    }

    /// Only the columns something was logged in: a family that only nurses
    /// has no use for a Bottle column, and five columns is already a squeeze.
    private func dayGrid(_ days: [DaySummaryGenerator.Report.Day]) -> some View {
        let showsBottle = days.contains { $0.volumeText != nil }
        let showsNursing = days.contains { $0.nursingText != nil }
        let showsDiapers = days.contains(where: \.hasDiapers)
        let columns = 2 + (showsBottle ? 1 : 0) + (showsNursing ? 1 : 0) + (showsDiapers ? 1 : 0)

        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                // The day column absorbs the slack so the numbers sit at the
                // right edge instead of the table hugging the left.
                Text("Day")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Feeds").gridColumnAlignment(.trailing)
                if showsBottle { Text("Bottle").gridColumnAlignment(.trailing) }
                if showsNursing { Text("Nursing").gridColumnAlignment(.trailing) }
                if showsDiapers { Text("Wet · dirty").gridColumnAlignment(.trailing) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Divider()
                .gridCellColumns(columns)

            ForEach(days) { day in
                GridRow {
                    Text(day.shortTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // A dash, not a 0, on a day with only diapers logged: it
                    // wasn't a day without feeds, just one nobody logged.
                    cell(day.feedCount > 0 ? "\(day.feedCount)" : nil)
                    if showsBottle { cell(day.volumeText) }
                    if showsNursing { cell(day.nursingText) }
                    if showsDiapers { cell(day.hasDiapers ? "\(day.wet) · \(day.dirty)" : nil) }
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
    }

    private func cell(_ text: String?) -> some View {
        Text(text ?? "–")
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(text == nil ? .secondary : .primary)
    }

    /// The foods, with first-times and reactions marked — "what are they
    /// eating?" and "any reactions?" get asked at every visit from six months.
    private func foodsSection(_ foods: [DaySummaryGenerator.Report.Food]) -> some View {
        Section {
            ForEach(foods) { food in
                HStack(alignment: .firstTextBaseline) {
                    Text(food.name)
                        .font(.subheadline)
                    if food.isFirstTime {
                        Text("first time")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if let reaction = food.reactionTitle {
                        Text(reaction)
                            .font(.caption)
                            .foregroundStyle(food.flagged ? .red : .secondary)
                    }
                    Spacer(minLength: 8)
                    Text(food.dateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Foods")
        }
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
            Text("Everything written down in this period.")
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
        .modelContainer(.preview)
}
