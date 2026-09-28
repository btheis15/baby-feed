import SwiftData
import SwiftUI

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
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \SolidFoodEntry.time, order: .reverse) private var foods: [SolidFoodEntry]
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    @State private var name = ""
    @State private var texture: FoodTexture = .puree
    @State private var reaction: FoodReaction = .ate
    @State private var time: Date = .now
    @State private var note = ""
    @State private var showDeleteConfirmation = false

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
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                    }
                }
            }
            .confirmationDialog("Delete this food?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Food", role: .destructive) { deleteEntry() }
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
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .new:
            let wasFirstTime = isFirstTime
            let entry = SolidFoodEntry(
                babyID: currentBabyID,
                time: time,
                name: trimmedName,
                texture: texture,
                reaction: reaction,
                note: trimmedNote,
                loggedByName: AppSettings.displayName
            )
            modelContext.insert(entry)
            FeedCoordinator.feedsDidChange(in: modelContext)
            toasts.logged(.food(entry, isFirstTime: wasFirstTime), detail: wasFirstTime ? "first time" : nil,
                          context: modelContext, router: router)
        case .edit(let entry):
            entry.name = trimmedName
            entry.texture = texture
            entry.reaction = reaction
            entry.time = time
            entry.note = trimmedNote
            entry.markChanged()
            FeedCoordinator.feedsDidChange(in: modelContext)
        }
        dismiss()
    }

    private func deleteEntry() {
        if case .edit(let entry) = mode {
            entry.softDelete()
            FeedCoordinator.feedsDidChange(in: modelContext)
        }
        dismiss()
    }
}

#Preview("New") {
    LogFoodSheet(mode: .new, ageMonths: 7)
        .environment(AppRouter())
        .environment(ToastCenter())
        .modelContainer(.preview)
}
