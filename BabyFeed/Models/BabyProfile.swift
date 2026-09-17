import Foundation

/// Baby's name and birthday, kept in UserDefaults (there's only ever one baby per install for now).
struct BabyProfile {
    static let nameKey = "baby.name"
    static let birthDateKey = "baby.birthDate"   // timeIntervalSince1970, 0 = unset

    var name: String
    var birthDate: Date?

    static func load(from defaults: UserDefaults = .standard) -> BabyProfile {
        let interval = defaults.double(forKey: birthDateKey)
        return BabyProfile(
            name: defaults.string(forKey: nameKey) ?? "",
            birthDate: interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        )
    }

    var displayName: String { name.isEmpty ? "Baby" : name }

    func ageInDays(on date: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let birthDate else { return nil }
        let start = calendar.startOfDay(for: birthDate)
        let end = calendar.startOfDay(for: date)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
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
