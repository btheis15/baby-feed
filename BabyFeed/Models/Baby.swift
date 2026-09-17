import Foundation
import SwiftData

/// A baby whose feeds are logged. Usually one; twins or a shared log you
/// joined make it more than one. Synced when `isShared`.
@Model
final class Baby {
    var uuid: UUID = UUID()
    var name: String = ""
    var birthDate: Date?
    /// Sex at birth, for the WHO growth percentiles. Stored as the raw value so
    /// adding a case later doesn't need a migration.
    var sexRaw: String = BabySex.unspecified.rawValue
    /// The original due date, for a baby born early. Usually nil.
    var dueDate: Date?
    /// True once the baby exists on the server and other caregivers can join.
    var isShared: Bool = false
    /// Supabase user id of the owner, when shared.
    var ownerUserID: String?
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var needsUpload: Bool = false

    init(uuid: UUID = UUID(), name: String, birthDate: Date?, sex: BabySex = .unspecified, dueDate: Date? = nil) {
        self.uuid = uuid
        self.name = name
        self.birthDate = birthDate
        self.sexRaw = sex.rawValue
        self.dueDate = dueDate
    }

    var displayName: String { name.isEmpty ? "Baby" : name }

    var sex: BabySex {
        get { BabySex(rawValue: sexRaw) ?? .unspecified }
        set { sexRaw = newValue.rawValue }
    }

    var profile: BabyProfile {
        BabyProfile(name: name, birthDate: birthDate, sex: sex, dueDate: dueDate)
    }

    func markChanged() {
        updatedAt = .now
        needsUpload = true
    }
}
