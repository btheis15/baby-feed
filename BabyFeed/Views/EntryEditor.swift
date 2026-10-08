import SwiftData
import SwiftUI

/// Opens the right editor for any row of the log. The timeline and the Edit
/// on a toast both come through here, so there's one answer to "how do I fix
/// that entry?", whatever kind it is.
struct EntryEditor: View {
    let ref: EntryRef

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces }

    /// Editing never age-gates a food: the texture it was logged with stays on
    /// offer even if the baby's age says something else today.
    private var ageMonths: Int {
        guard birthInterval > 0 else { return 12 }
        let days = AppSettings.calendar.dateComponents(
            [.day], from: Date(timeIntervalSince1970: birthInterval), to: .now
        ).day ?? 0
        return max(12, FoodGuidance.months(fromDays: days))
    }

    var body: some View {
        switch ref {
        case .feed(let id):
            if let entry = modelContext.model(for: id) as? FeedEntry {
                LogFeedSheet(mode: .edit(entry))
            } else {
                missing
            }
        case .diaper(let id):
            if let entry = modelContext.model(for: id) as? DiaperEntry {
                LogDiaperSheet(mode: .edit(entry))
            } else {
                missing
            }
        case .food(let id):
            if let entry = modelContext.model(for: id) as? SolidFoodEntry {
                LogFoodSheet(mode: .edit(entry), ageMonths: ageMonths)
            } else {
                missing
            }
        case .weight(let id):
            if let entry = modelContext.model(for: id) as? WeightEntry {
                AddWeightSheet(weightUnit: weightUnit, mode: .edit(entry))
            } else {
                missing
            }
        case .note(let id):
            if let entry = modelContext.model(for: id) as? CareNote {
                if entry.kind == .allFine {
                    // A marker, not a note: unmarking it happens where it was marked.
                    FineDaysSheet(babyID: entry.babyID)
                } else {
                    LogCareNoteSheet(mode: .edit(entry))
                }
            } else {
                missing
            }
        case .concern(let id):
            if let entry = modelContext.model(for: id) as? HealthConcern {
                LogConcernSheet(mode: .edit(entry))
            } else {
                missing
            }
        case .dose(let id):
            if let entry = modelContext.model(for: id) as? MedicationDose {
                LogDoseSheet(mode: .edit(entry))
            } else {
                missing
            }
        case .visit(let id):
            if let entry = modelContext.model(for: id) as? DoctorVisit {
                DoctorVisitSheet(mode: .edit(entry))
            } else {
                missing
            }
        case .medication(let id):
            if let entry = modelContext.model(for: id) as? Medication {
                MedicationSheet(mode: .edit(entry))
            } else {
                missing
            }
        }
    }

    /// Only reachable if the row vanished between the tap and the sheet — the
    /// other phone deleted it mid-sync, say.
    private var missing: some View {
        NavigationStack {
            ContentUnavailableView("That entry is gone", systemImage: "questionmark.circle",
                                   description: Text("It may have been deleted on another phone."))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}
