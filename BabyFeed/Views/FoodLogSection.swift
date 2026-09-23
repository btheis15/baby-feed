import SwiftData
import SwiftUI

/// Logging what the baby actually ate, once they're old enough that anything
/// beyond milk is on the table.
///
/// The whole section is age-gated: it doesn't exist before four months, and
/// the textures it offers unlock on the same AAP boundaries the Foods-by-age
/// screen cites — purées in the readiness window, mashed food from six months,
/// finger foods from nine, family food from twelve. The caller passes the age;
/// this view never re-derives it, so the two screens can't disagree.
struct FoodLogSection: View {
    let ageMonths: Int

    @Query(sort: \SolidFoodEntry.time, order: .reverse) private var foods: [SolidFoodEntry]
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    @State private var showLogSheet = false

    private var currentBabyID: UUID? { UUID(uuidString: currentBabyIDRaw) }

    var body: some View {
        let visible = foods.active(for: currentBabyID)
        let today = visible.filter { Calendar.current.isDateInToday($0.time) }

        VStack(spacing: 12) {
            Button {
                showLogSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "carrot.fill")
                        .font(.system(size: 22))
                    Text("Log a food")
                        .font(.headline)
                    Spacer()
                    Text(ageMonths < 6 ? "From 4 months, if ready" : "\(visible.distinctNames.count) tried")
                        .font(.subheadline)
                        .opacity(0.75)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log a food")

            HStack {
                Text(today.isEmpty
                     ? "Nothing solid today"
                     : "Today: \(today.map(\.name).joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if !visible.isEmpty {
                    NavigationLink {
                        FoodListView(ageMonths: ageMonths)
                    } label: {
                        Text("All foods")
                            .font(.footnote)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .sheet(isPresented: $showLogSheet) {
            LogFoodSheet(mode: .new, ageMonths: ageMonths)
        }
    }
}

/// Everything the baby has eaten, newest first — the record that answers
/// "has she had egg before?" when it suddenly matters.
struct FoodListView: View {
    let ageMonths: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Query(sort: \SolidFoodEntry.time, order: .reverse) private var foods: [SolidFoodEntry]
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    @State private var editing: SolidFoodEntry?

    private var currentBabyID: UUID? { UUID(uuidString: currentBabyIDRaw) }

    var body: some View {
        let visible = foods.active(for: currentBabyID)
        let groups = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.time) }
            .sorted { $0.key > $1.key }

        List {
            ForEach(groups, id: \.key) { day, entries in
                Section(FeedStats.dayTitle(for: day, calendar: calendar)) {
                    ForEach(entries) { entry in
                        row(entry, isFirst: visible.isFirstTime(entry))
                            .contentShape(Rectangle())
                            .onTapGesture { editing = entry }
                    }
                    .onDelete { offsets in
                        delete(offsets.map { entries[$0] })
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Foods")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { entry in
            LogFoodSheet(mode: .edit(entry), ageMonths: ageMonths)
        }
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView(
                    "No foods yet",
                    systemImage: "carrot.fill",
                    description: Text("Log the first taste from the Today screen.")
                )
            }
        }
    }

    private func row(_ entry: SolidFoodEntry, isFirst: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.reaction.systemImage)
                .foregroundStyle(entry.reaction.color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.body)
                    if isFirst {
                        Text("First time")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                Text(detailText(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.time.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func detailText(_ entry: SolidFoodEntry) -> String {
        var parts = [entry.texture.title, entry.reaction.title]
        if !entry.loggedByName.isEmpty { parts.append("by \(entry.loggedByName)") }
        return parts.joined(separator: " · ")
    }

    private func delete(_ toDelete: [SolidFoodEntry]) {
        withAnimation {
            for entry in toDelete { entry.softDelete() }
        }
        try? modelContext.save()
        SyncEngine.shared.requestSync()
    }
}

/// One food, one sheet. The texture options are the age-gate: only what the
/// AAP stages open up at this baby's age is offered at all.
struct LogFoodSheet: View {
    enum Mode {
        case new
        case edit(SolidFoodEntry)
    }

    let mode: Mode
    let ageMonths: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SolidFoodEntry.time, order: .reverse) private var foods: [SolidFoodEntry]
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    @State private var name = ""
    @State private var texture: FoodTexture = .puree
    @State private var reaction: FoodReaction = .ate
    @State private var time: Date = .now
    @State private var note = ""

    private var currentBabyID: UUID? { UUID(uuidString: currentBabyIDRaw) }
    private var availableTextures: [FoodTexture] { FoodTexture.available(atMonths: ageMonths) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// True when nothing in the log has this name yet — worth saying out loud,
    /// because "one new food at a time" only works if you notice it's new.
    private var isFirstTime: Bool {
        let key = SolidFoodEntry.normalized(name)
        guard !key.isEmpty else { return false }
        if case .edit(let entry) = mode, entry.normalizedName == key { return false }
        return !foods.active(for: currentBabyID).contains { $0.normalizedName == key }
    }

    private var suggestions: [String] {
        let typed = SolidFoodEntry.normalized(name)
        let names = foods.active(for: currentBabyID).distinctNames
        guard !typed.isEmpty else { return Array(names.prefix(8)) }
        return names.filter { SolidFoodEntry.normalized($0).hasPrefix(typed) && SolidFoodEntry.normalized($0) != typed }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Sweet potato, oat cereal, egg…", text: $name)
                        .textInputAutocapitalization(.words)

                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button(suggestion) { name = suggestion }
                                        .font(.subheadline)
                                        .buttonStyle(.bordered)
                                        .buttonBorderShape(.capsule)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                } header: {
                    Text("What")
                } footer: {
                    if isFirstTime {
                        Label("First time. The AAP suggests one new food at a time, 3–5 days apart, so a reaction is easy to trace.",
                              systemImage: "sparkles")
                    }
                }

                Section {
                    Picker("How it was served", selection: $texture) {
                        ForEach(availableTextures) { texture in
                            Text(texture.title).tag(texture)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("How")
                } footer: {
                    Text(textureFooter)
                }

                Section("How it went") {
                    Picker("Reaction", selection: $reaction) {
                        ForEach(FoodReaction.allCases) { reaction in
                            Text(reaction.title).tag(reaction)
                        }
                    }
                    .pickerStyle(.segmented)

                    if reaction == .possibleReaction {
                        Text("Rash, vomiting, swelling, or trouble breathing after a food is worth a call to the pediatrician — and 911 for trouble breathing.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    DatePicker("When", selection: $time, in: ...Date.now)
                    TextField("Optional – how much, mixed with what…", text: $note)
                }

                if case .edit(let entry) = mode {
                    Section {
                        Button("Delete", role: .destructive) {
                            entry.softDelete()
                            try? modelContext.save()
                            SyncEngine.shared.requestSync()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit food" : "Log a food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// Why these textures and not others — the stage's own words, cited on the
    /// Foods-by-age screen.
    private var textureFooter: String {
        switch FoodGuidance.stage(forMonths: ageMonths).id {
        case "watch-for-readiness":
            "Purées are possible from 4 months if your baby is clearly ready; around 6 months is the AAP's recommendation. More textures unlock as they grow."
        case "first-foods":
            "Purées and well-mashed food at this age. Iron-rich foods first, one new food at a time."
        case "more-texture":
            "Soft finger foods cut small are on the menu from 9 months, alongside lumpier textures."
        default:
            "From 12 months, the same food the family eats, chopped small, without added salt or sugar."
        }
    }

    private func prefill() {
        if case .edit(let entry) = mode {
            name = entry.name
            texture = entry.texture
            reaction = entry.reaction
            time = entry.time
            note = entry.note
        } else {
            // The newest texture the age allows is the likeliest one to log.
            texture = availableTextures.last ?? .puree
        }
        // An old entry can carry a texture the pickers no longer offer only if
        // the age somehow went down; the gate is about offering, not editing.
        if !availableTextures.contains(texture) { texture = availableTextures.first ?? .puree }
    }

    private func save() {
        switch mode {
        case .new:
            let entry = SolidFoodEntry(
                babyID: currentBabyID,
                time: time,
                name: trimmedName,
                texture: texture,
                reaction: reaction,
                note: note,
                loggedByName: AppSettings.displayName
            )
            modelContext.insert(entry)
        case .edit(let entry):
            entry.name = trimmedName
            entry.texture = texture
            entry.reaction = reaction
            entry.time = time
            entry.note = note
            entry.markChanged()
        }
        try? modelContext.save()
        SyncEngine.shared.requestSync()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        List {
            Section("Foods") { FoodLogSection(ageMonths: 7) }
        }
    }
    .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self, CareNote.self,
                          DiaperEntry.self, SolidFoodEntry.self], inMemory: true)
}
