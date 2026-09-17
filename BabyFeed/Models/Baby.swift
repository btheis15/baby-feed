import Foundation
import SwiftData

/// A baby whose feeds are logged. Usually one; twins or a shared log you
/// joined make it more than one. Synced when `isShared`.
@Model
final class Baby {
    var uuid: UUID = UUID()
    var name: String = ""
    var birthDate: Date?
    /// True once the baby exists on the server and other caregivers can join.
    var isShared: Bool = false
    /// Supabase user id of the owner, when shared.
    var ownerUserID: String?
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var needsUpload: Bool = false

    init(uuid: UUID = UUID(), name: String, birthDate: Date?) {
        self.uuid = uuid
        self.name = name
        self.birthDate = birthDate
    }

    var displayName: String { name.isEmpty ? "Baby" : name }

    var profile: BabyProfile { BabyProfile(name: name, birthDate: birthDate) }

    func markChanged() {
        updatedAt = .now
        needsUpload = true
    }
}
