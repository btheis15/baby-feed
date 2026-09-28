import Foundation
import SwiftData

/// Owns the "current baby" and keeps the UserDefaults `BabyProfile` mirror
/// (which the rest of the app reads) in step with the synced `Baby` model.
@MainActor
enum BabyStore {
    /// Run once at launch. Guarantees a current baby exists and that every
    /// feed/weight has a uuid and belongs to a baby.
    static func bootstrap(in context: ModelContext) {
        let babies = (try? context.fetch(FetchDescriptor<Baby>(sortBy: [SortDescriptor(\.updatedAt)]))) ?? []
        var current = babies.first { $0.uuid == AppSettings.currentBabyID && $0.deletedAt == nil }
            ?? babies.first { $0.deletedAt == nil }

        if current == nil {
            // First launch (or upgrade from the profile-in-defaults version).
            let profile = BabyProfile.load()
            let baby = Baby(
                name: profile.name,
                birthDate: profile.birthDate,
                sex: profile.sex,
                dueDate: profile.dueDate
            )
            context.insert(baby)
            current = baby
        }

        guard let current else { return }
        AppSettings.currentBabyID = current.uuid
        mirrorToDefaults(current)

        // Adopt rows from before sync existed.
        let feeds = (try? context.fetch(FetchDescriptor<FeedEntry>())) ?? []
        for feed in feeds {
            if feed.uuid == nil { feed.uuid = UUID() }
            if feed.babyID == nil { feed.babyID = current.uuid }
        }
        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []
        for weight in weights {
            if weight.uuid == nil { weight.uuid = UUID() }
            if weight.babyID == nil { weight.babyID = current.uuid }
        }
        let careNotes = (try? context.fetch(FetchDescriptor<CareNote>())) ?? []
        for careNote in careNotes {
            if careNote.uuid == nil { careNote.uuid = UUID() }
            if careNote.babyID == nil { careNote.babyID = current.uuid }
        }
        try? context.save()
    }

    static func currentBaby(in context: ModelContext) -> Baby? {
        guard let id = AppSettings.currentBabyID else { return nil }
        let descriptor = FetchDescriptor<Baby>(predicate: #Predicate { $0.uuid == id })
        return try? context.fetch(descriptor).first
    }

    static func baby(withID id: UUID, in context: ModelContext) -> Baby? {
        let descriptor = FetchDescriptor<Baby>(predicate: #Predicate { $0.uuid == id })
        return try? context.fetch(descriptor).first
    }

    static func allBabies(in context: ModelContext) -> [Baby] {
        let babies = (try? context.fetch(FetchDescriptor<Baby>(sortBy: [SortDescriptor(\.name)]))) ?? []
        return babies.filter { $0.deletedAt == nil }
    }

    static func setCurrent(_ baby: Baby, in context: ModelContext) {
        AppSettings.currentBabyID = baby.uuid
        mirrorToDefaults(baby)
        FeedCoordinator.settingsDidChange(in: context)
    }

    /// The Baby tab edits the UserDefaults profile directly; call this after
    /// so the synced model picks up the change.
    static func profileDefaultsChanged(in context: ModelContext) {
        guard let baby = currentBaby(in: context) else { return }
        let profile = BabyProfile.load()
        var changed = false
        if baby.name != profile.name {
            baby.name = profile.name
            changed = true
        }
        if baby.birthDate != profile.birthDate {
            baby.birthDate = profile.birthDate
            changed = true
        }
        if baby.sex != profile.sex {
            baby.sex = profile.sex
            changed = true
        }
        if baby.dueDate != profile.dueDate {
            baby.dueDate = profile.dueDate
            changed = true
        }
        if changed {
            baby.markChanged()
            try? context.save()
            SyncEngine.shared.requestSync()
        }
    }

    /// Server or another caregiver changed the baby; push it into the mirror
    /// if it's the one on screen.
    static func mirrorToDefaults(_ baby: Baby) {
        guard baby.uuid == AppSettings.currentBabyID else { return }
        let defaults = UserDefaults.standard
        defaults.set(baby.name, forKey: BabyProfile.nameKey)
        defaults.set(baby.birthDate?.timeIntervalSince1970 ?? 0, forKey: BabyProfile.birthDateKey)
        defaults.set(baby.sexRaw, forKey: BabyProfile.sexKey)
        defaults.set(baby.dueDate?.timeIntervalSince1970 ?? 0, forKey: BabyProfile.dueDateKey)
    }

    /// Adds a new local baby (e.g. a twin) and makes it current.
    static func addBaby(
        name: String,
        birthDate: Date?,
        sex: BabySex = .unspecified,
        dueDate: Date? = nil,
        in context: ModelContext
    ) -> Baby {
        let baby = Baby(name: name, birthDate: birthDate, sex: sex, dueDate: dueDate)
        context.insert(baby)
        try? context.save()
        setCurrent(baby, in: context)
        return baby
    }

    // MARK: Placeholders

    /// How many rows of any kind this baby has, deleted or not.
    static func rowCount(for id: UUID, in context: ModelContext) -> Int {
        let feeds = (try? context.fetchCount(FetchDescriptor<FeedEntry>(predicate: #Predicate { $0.babyID == id }))) ?? 0
        let diapers = (try? context.fetchCount(FetchDescriptor<DiaperEntry>(predicate: #Predicate { $0.babyID == id }))) ?? 0
        let weights = (try? context.fetchCount(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.babyID == id }))) ?? 0
        let notes = (try? context.fetchCount(FetchDescriptor<CareNote>(predicate: #Predicate { $0.babyID == id }))) ?? 0
        let foods = (try? context.fetchCount(FetchDescriptor<SolidFoodEntry>(predicate: #Predicate { $0.babyID == id }))) ?? 0
        let concerns = (try? context.fetchCount(FetchDescriptor<HealthConcern>(predicate: #Predicate { $0.babyID == id }))) ?? 0
        let medications = (try? context.fetchCount(FetchDescriptor<Medication>(predicate: #Predicate { $0.babyID == id }))) ?? 0
        let doses = (try? context.fetchCount(FetchDescriptor<MedicationDose>(predicate: #Predicate { $0.babyID == id }))) ?? 0
        let visits = (try? context.fetchCount(FetchDescriptor<DoctorVisit>(predicate: #Predicate { $0.babyID == id }))) ?? 0
        return feeds + diapers + weights + notes + foods + concerns + medications + doses + visits
    }

    /// The nameless, empty baby a fresh install starts with. It's never
    /// uploaded, and joining or restoring a log replaces it.
    static func isPlaceholder(_ baby: Baby, in context: ModelContext) -> Bool {
        SyncPlan.isPlaceholder(name: baby.name, birthDate: baby.birthDate, isShared: baby.isShared,
                               rowCount: rowCount(for: baby.uuid, in: context))
    }

    /// Every baby worth backing up: not deleted, and not the placeholder.
    static func realBabies(in context: ModelContext) -> [Baby] {
        allBabies(in: context).filter { !isPlaceholder($0, in: context) }
    }

    /// Adding the baby from onboarding. Fills in the placeholder when that's
    /// the only baby, rather than leaving an empty one beside it. A birth
    /// weight becomes the first weigh-in, dated the birthday, which is what
    /// "back to birth weight" is measured from.
    @discardableResult
    static func createBaby(
        name: String,
        birthDate: Date?,
        sex: BabySex = .unspecified,
        dueDate: Date? = nil,
        birthWeightGrams: Double? = nil,
        in context: ModelContext
    ) -> Baby {
        let existing = allBabies(in: context)
        let baby: Baby
        if existing.count == 1, let only = existing.first, isPlaceholder(only, in: context) {
            baby = only
        } else {
            baby = Baby(name: name, birthDate: birthDate)
            context.insert(baby)
        }
        baby.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        baby.birthDate = birthDate
        baby.sex = sex
        baby.dueDate = dueDate
        baby.markChanged()

        if let birthWeightGrams, birthWeightGrams > 0 {
            context.insert(WeightEntry(
                babyID: baby.uuid,
                date: birthDate ?? .now,
                grams: birthWeightGrams,
                note: "Birth weight",
                loggedByName: AppSettings.displayName
            ))
        }
        try? context.save()
        setCurrent(baby, in: context)
        return baby
    }

    /// Drops untouched placeholders once a real log has arrived, so the baby
    /// switcher doesn't offer an empty "Baby" next to the one just joined.
    static func removePlaceholders(keeping keep: UUID?, in context: ModelContext) {
        for baby in allBabies(in: context) where baby.uuid != keep && isPlaceholder(baby, in: context) {
            context.delete(baby)
        }
        try? context.save()
    }

    /// Removes a baby and every row it has from this phone only. Nothing is
    /// sent to the server, and nobody else's copy changes.
    static func removeLocally(_ baby: Baby, in context: ModelContext) {
        let id = baby.uuid

        // Switch away first, so nothing on screen is left reading a baby
        // that's about to stop existing.
        if AppSettings.currentBabyID == id {
            if let next = allBabies(in: context).first(where: { $0.uuid != id }) {
                setCurrent(next, in: context)
            } else {
                let fresh = Baby(name: "", birthDate: nil)
                context.insert(fresh)
                try? context.save()
                setCurrent(fresh, in: context)
            }
        }

        // Every table that carries a babyID. Diapers and solid foods were
        // missing here once, and lingered as rows nothing could show or delete.
        let feeds = (try? context.fetch(FetchDescriptor<FeedEntry>(predicate: #Predicate { $0.babyID == id }))) ?? []
        feeds.forEach(context.delete)
        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.babyID == id }))) ?? []
        weights.forEach(context.delete)
        let careNotes = (try? context.fetch(FetchDescriptor<CareNote>(predicate: #Predicate { $0.babyID == id }))) ?? []
        careNotes.forEach(context.delete)
        let diapers = (try? context.fetch(FetchDescriptor<DiaperEntry>(predicate: #Predicate { $0.babyID == id }))) ?? []
        diapers.forEach(context.delete)
        let foods = (try? context.fetch(FetchDescriptor<SolidFoodEntry>(predicate: #Predicate { $0.babyID == id }))) ?? []
        foods.forEach(context.delete)
        let concerns = (try? context.fetch(FetchDescriptor<HealthConcern>(predicate: #Predicate { $0.babyID == id }))) ?? []
        concerns.forEach(context.delete)
        let medications = (try? context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.babyID == id }))) ?? []
        medications.forEach(context.delete)
        let doses = (try? context.fetch(FetchDescriptor<MedicationDose>(predicate: #Predicate { $0.babyID == id }))) ?? []
        doses.forEach(context.delete)
        let visits = (try? context.fetch(FetchDescriptor<DoctorVisit>(predicate: #Predicate { $0.babyID == id }))) ?? []
        visits.forEach(context.delete)
        context.delete(baby)
        try? context.save()
    }
}
