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
            let baby = Baby(name: profile.name, birthDate: profile.birthDate)
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
    }

    /// Adds a new local baby (e.g. a twin) and makes it current.
    static func addBaby(name: String, birthDate: Date?, in context: ModelContext) -> Baby {
        let baby = Baby(name: name, birthDate: birthDate)
        context.insert(baby)
        try? context.save()
        setCurrent(baby, in: context)
        return baby
    }

    /// Removes a baby and its data from this phone only.
    static func removeLocally(_ baby: Baby, in context: ModelContext) {
        let id = baby.uuid
        let feeds = (try? context.fetch(FetchDescriptor<FeedEntry>(predicate: #Predicate { $0.babyID == id }))) ?? []
        feeds.forEach(context.delete)
        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.babyID == id }))) ?? []
        weights.forEach(context.delete)
        context.delete(baby)
        try? context.save()

        if AppSettings.currentBabyID == id {
            if let next = allBabies(in: context).first {
                setCurrent(next, in: context)
            } else {
                let fresh = Baby(name: "", birthDate: nil)
                context.insert(fresh)
                try? context.save()
                setCurrent(fresh, in: context)
            }
        }
    }
}
