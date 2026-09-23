import Foundation
import SwiftData
import SwiftUI

/// One food the baby actually ate — the log that grows up with the child.
///
/// Feeds are milk; this is everything after. It exists for two questions that
/// matter later: "has she had egg before?" when tracing a reaction, and "what
/// does he actually eat?" at the twelve-month appointment. So each entry is a
/// named food, how it was served, and how it went down.
///
/// Sync fields mirror `FeedEntry`: `uuid` identifies the row across devices,
/// `babyID` says whose log it is, `updatedAt` decides conflicts, `deletedAt` is
/// a soft delete, `needsUpload` queues the next push.
@Model
final class SolidFoodEntry {
    var uuid: UUID?
    var babyID: UUID?
    var time: Date = Date()
    /// The food, as the caregiver names it: "Avocado", "Oat cereal".
    var name: String = ""
    var textureRaw: String = FoodTexture.puree.rawValue
    var reactionRaw: String = FoodReaction.ate.rawValue
    var note: String = ""
    var loggedByName: String = ""
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var needsUpload: Bool = true

    init(
        uuid: UUID = UUID(),
        babyID: UUID? = nil,
        time: Date = .now,
        name: String,
        texture: FoodTexture,
        reaction: FoodReaction = .ate,
        note: String = "",
        loggedByName: String = ""
    ) {
        self.uuid = uuid
        self.babyID = babyID
        self.time = time
        self.name = name
        self.textureRaw = texture.rawValue
        self.reactionRaw = reaction.rawValue
        self.note = note
        self.loggedByName = loggedByName
        self.updatedAt = .now
        self.needsUpload = true
    }

    var texture: FoodTexture {
        get { FoodTexture(rawValue: textureRaw) ?? .puree }
        set { textureRaw = newValue.rawValue }
    }

    var reaction: FoodReaction {
        get { FoodReaction(rawValue: reactionRaw) ?? .ate }
        set { reactionRaw = newValue.rawValue }
    }

    /// "avocado" == "Avocado " — one food, however it was typed, so the
    /// first-time check can't be fooled by capitalisation.
    var normalizedName: String { Self.normalized(name) }

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func markChanged() {
        updatedAt = .now
        needsUpload = true
    }

    func softDelete() {
        deletedAt = .now
        markChanged()
    }
}

/// How the food was served. Which of these are offered is gated by age, and
/// the boundaries are `FoodGuidance.stages`' own — 4, 6, 9 and 12 months, each
/// carrying the AAP/CDC citations on that screen. One age model, not two that
/// could drift apart.
enum FoodTexture: String, CaseIterable, Identifiable, Codable {
    case puree
    case mashed
    case fingerFood
    case familyFood

    var id: String { rawValue }

    /// Inclusive lower bound, matching the FoodGuidance stage that first
    /// mentions it: purées from the readiness window (4–6, recommended around
    /// 6), mashed with first foods (6), finger foods with more texture (9),
    /// family food at twelve months.
    var availableFromMonths: Int {
        switch self {
        case .puree: 4
        case .mashed: 6
        case .fingerFood: 9
        case .familyFood: 12
        }
    }

    var title: String {
        switch self {
        case .puree: "Purée"
        case .mashed: "Mashed"
        case .fingerFood: "Finger food"
        case .familyFood: "Family food"
        }
    }

    var systemImage: String {
        switch self {
        case .puree: "cup.and.saucer.fill"
        case .mashed: "fork.knife"
        case .fingerFood: "hand.pinch.fill"
        case .familyFood: "fork.knife.circle.fill"
        }
    }

    /// The textures a baby of this age can be offered, per the AAP stages.
    /// Empty before four months — no solids, so no UI.
    static func available(atMonths months: Int) -> [FoodTexture] {
        allCases.filter { months >= $0.availableFromMonths }
    }
}

/// How it went. `possibleReaction` is the one that earns its place: the AAP's
/// one-new-food-at-a-time advice exists so a reaction can be traced, and a
/// reaction nobody wrote down can't be.
enum FoodReaction: String, CaseIterable, Identifiable, Codable {
    case loved
    case ate
    case refused
    case possibleReaction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loved: "Loved it"
        case .ate: "Ate it"
        case .refused: "Refused"
        case .possibleReaction: "Reaction?"
        }
    }

    var systemImage: String {
        switch self {
        case .loved: "face.smiling.inverse"
        case .ate: "checkmark.circle.fill"
        case .refused: "xmark.circle.fill"
        case .possibleReaction: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .loved: .green
        case .ate: .secondary
        case .refused: .orange
        case .possibleReaction: .red
        }
    }
}

extension Array where Element == SolidFoodEntry {
    func active(for babyID: UUID?) -> [SolidFoodEntry] {
        filter { $0.deletedAt == nil && (babyID == nil || $0.babyID == babyID) }
    }

    /// Whether this exact food has never been logged before `entry` — the
    /// "first time" badge, and the reason tracing a reaction is possible.
    func isFirstTime(_ entry: SolidFoodEntry) -> Bool {
        let name = entry.normalizedName
        guard !name.isEmpty else { return false }
        return !contains {
            $0.deletedAt == nil && $0.uuid != entry.uuid
                && $0.normalizedName == name && $0.time < entry.time
        }
    }

    /// Distinct foods already logged, most recent first — the suggestions when
    /// typing, so "sweet potato" is one tap the second time.
    var distinctNames: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for entry in sorted(by: { $0.time > $1.time }) where entry.deletedAt == nil {
            let key = entry.normalizedName
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            names.append(entry.name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return names
    }
}
