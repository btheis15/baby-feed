import Foundation

/// Baby's name and birthday, kept in UserDefaults (there's only ever one baby per install for now).
struct BabyProfile: Equatable {
    static let nameKey = "baby.name"
    static let birthDateKey = "baby.birthDate"   // timeIntervalSince1970, 0 = unset
    static let sexKey = "baby.sex"
    static let dueDateKey = "baby.dueDate"       // timeIntervalSince1970, 0 = unset

    var name: String
    var birthDate: Date?
    /// Only used for WHO percentiles, which are sex-specific.
    var sex: BabySex = .unspecified
    /// The original due date, for babies born early. Optional and usually nil.
    var dueDate: Date?

    static func load(from defaults: UserDefaults = .standard) -> BabyProfile {
        let interval = defaults.double(forKey: birthDateKey)
        let due = defaults.double(forKey: dueDateKey)
        return BabyProfile(
            name: defaults.string(forKey: nameKey) ?? "",
            birthDate: interval > 0 ? Date(timeIntervalSince1970: interval) : nil,
            sex: BabySex(rawValue: defaults.string(forKey: sexKey) ?? "") ?? .unspecified,
            dueDate: due > 0 ? Date(timeIntervalSince1970: due) : nil
        )
    }

    var displayName: String { name.isEmpty ? "Baby" : name }

    func ageInDays(on date: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let birthDate else { return nil }
        let start = calendar.startOfDay(for: birthDate)
        let end = calendar.startOfDay(for: date)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    /// True when the due date says the baby arrived more than three weeks early,
    /// the point at which plotting actual age against term standards misleads.
    var isPreterm: Bool {
        guard let birthDate, let dueDate else { return false }
        return dueDate.timeIntervalSince(birthDate) > 21 * 24 * 3600
    }

    /// Age to plot on the WHO charts, in days, which may be fractional.
    ///
    /// A baby born early is plotted at *corrected* age – measured from the due
    /// date, not the birthday – because WHO's standards describe babies born at
    /// term. Without this a 34-weeker reads as alarmingly small. Negative
    /// before the due date passes, where the term standards simply don't apply.
    func growthAgeDays(on date: Date = .now) -> Double? {
        guard let birthDate else { return nil }
        let anchor = dueDate ?? birthDate
        return date.timeIntervalSince(anchor) / (24 * 3600)
    }

    /// "3 days old", "2 weeks old", "3 months old".
    func ageText(on date: Date = .now, calendar: Calendar = .current) -> String? {
        guard let days = ageInDays(on: date, calendar: calendar) else { return nil }
        if days < 14 { return days == 1 ? "1 day old" : "\(days) days old" }
        if days < 84 {
            let weeks = days / 7
            let extra = days % 7
            return extra == 0 ? "\(weeks) weeks old" : "\(weeks)w \(extra)d old"
        }
        let months = calendar.dateComponents([.month], from: birthDate!, to: date).month ?? 0
        return months == 1 ? "1 month old" : "\(months) months old"
    }
}

extension BabyProfile {
    /// Built from the raw values a screen holds in `@AppStorage`.
    ///
    /// `load(from:)` reads the same four keys, but a view has to bind to each
    /// one individually to re-render when it changes — so it holds the raw
    /// `Double`/`String` and needs this to get back to a profile. Today,
    /// History and Baby each carried their own copy of the conversion, which
    /// meant a fifth profile field had to be remembered in three places.
    ///
    /// In an extension so the memberwise initialiser survives: `Baby.profile`
    /// builds one from real `Date`s.
    init(name: String, birthInterval: Double, sexRaw: String, dueInterval: Double) {
        self.init(
            name: name,
            birthDate: birthInterval > 0 ? Date(timeIntervalSince1970: birthInterval) : nil,
            sex: BabySex(rawValue: sexRaw) ?? .unspecified,
            dueDate: dueInterval > 0 ? Date(timeIntervalSince1970: dueInterval) : nil
        )
    }
}
