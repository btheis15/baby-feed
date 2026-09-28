import SwiftUI

/// What "+ Log something else" offers: everything that isn't a feed or a
/// diaper. Those two are what gets logged many times a day, so they keep their
/// own buttons on Today; the rest waits one tap further in. Later phases add
/// medicine, a concern and a doctor visit here.
enum AddEntryKind: String, CaseIterable, Identifiable {
    case note
    case weight
    case food

    var id: String { rawValue }

    var title: String {
        switch self {
        case .note: "Note"
        case .weight: "Weight"
        case .food: "Food"
        }
    }

    var subtitle: String {
        switch self {
        case .note: "Breathing, a rash, spit-up, a bad night: anything for the doctor"
        case .weight: "From the scale at home or a checkup"
        case .food: "Solids, one new food at a time"
        }
    }

    var systemImage: String {
        switch self {
        case .note: "note.text"
        case .weight: "scalemass.fill"
        case .food: "carrot.fill"
        }
    }

    var tint: Color {
        switch self {
        case .note: .purple
        case .weight: .blue
        case .food: .green
        }
    }
}

/// The short list behind "+ Log something else".
struct AddEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(AppRouter.self) private var router
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0

    /// Food only once the AAP stages open anything beyond milk: before four
    /// months, or with no birthday set, there is nothing to log.
    private var kinds: [AddEntryKind] {
        AddEntryKind.allCases.filter { kind in
            guard kind == .food else { return true }
            guard let months = NewEntrySheet.ageMonths(birthInterval: birthInterval, calendar: calendar) else { return false }
            return !FoodTexture.available(atMonths: months).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            List(kinds) { kind in
                Button {
                    // Replacing the sheet closes this one and opens that one.
                    router.sheet = .newEntry(kind)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: kind.systemImage)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(kind.tint, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                                .font(.headline)
                            Text(kind.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Log something else")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The sheet for a new entry of one of those kinds.
struct NewEntrySheet: View {
    let kind: AddEntryKind

    @Environment(\.calendar) private var calendar
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0

    /// Whole months old, the unit the food stages are written in; nil with no
    /// birthday set.
    static func ageMonths(birthInterval: Double, calendar: Calendar, now: Date = .now) -> Int? {
        guard birthInterval > 0 else { return nil }
        let profile = BabyProfile(name: "", birthDate: Date(timeIntervalSince1970: birthInterval))
        return profile.ageInDays(on: now, calendar: calendar).map(FoodGuidance.months(fromDays:))
    }

    var body: some View {
        switch kind {
        case .note:
            LogCareNoteSheet(mode: .new)
        case .weight:
            AddWeightSheet(weightUnit: WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces)
        case .food:
            LogFoodSheet(mode: .new, ageMonths: Self.ageMonths(birthInterval: birthInterval, calendar: calendar) ?? 6)
        }
    }
}

#Preview {
    AddEntrySheet()
        .environment(AppRouter())
}
