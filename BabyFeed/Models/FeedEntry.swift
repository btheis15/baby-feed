import Foundation
import SwiftData

/// One feed. Bottle feeds carry a volume (always stored in ml);
/// nursing carries a duration and optionally a side.
///
/// Sync fields: `uuid` identifies the row across devices, `babyID` says whose
/// log it belongs to, `updatedAt` decides conflicts, `deletedAt` is a soft
/// delete so removals propagate, and `needsUpload` queues it for the next push.
@Model
final class FeedEntry {
    var uuid: UUID?
    var babyID: UUID?
    var startTime: Date = Date()
    var kindRaw: String = FeedKind.formula.rawValue
    var amountML: Double?
    var durationMinutes: Int?
    var sideRaw: String?
    var note: String = ""
    /// Display name of whoever logged it, for shared logs.
    var loggedByName: String = ""
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var needsUpload: Bool = true

    init(
        uuid: UUID = UUID(),
        babyID: UUID? = nil,
        startTime: Date = .now,
        kind: FeedKind,
        amountML: Double? = nil,
        durationMinutes: Int? = nil,
        side: NursingSide? = nil,
        note: String = "",
        loggedByName: String = ""
    ) {
        self.uuid = uuid
        self.babyID = babyID
        self.startTime = startTime
        self.kindRaw = kind.rawValue
        self.amountML = amountML
        self.durationMinutes = durationMinutes
        self.sideRaw = side?.rawValue
        self.note = note
        self.loggedByName = loggedByName
        self.updatedAt = .now
        self.needsUpload = true
    }

    var kind: FeedKind {
        get { FeedKind(rawValue: kindRaw) ?? .formula }
        set { kindRaw = newValue.rawValue }
    }

    var side: NursingSide? {
        get { sideRaw.flatMap(NursingSide.init(rawValue:)) }
        set { sideRaw = newValue?.rawValue }
    }

    /// Call after editing so the change is timestamped and queued for sync.
    func markChanged() {
        updatedAt = .now
        needsUpload = true
    }

    func softDelete() {
        deletedAt = .now
        markChanged()
    }

    /// "3 oz" / "15 min · Left" – the short description used in lists.
    func detailText(unit: VolumeUnit) -> String {
        switch kind {
        case .formula, .breastMilk:
            if let amountML {
                return unit.format(milliliters: amountML)
            }
            return "Bottle"
        case .nursing:
            var parts: [String] = []
            if let durationMinutes {
                parts.append("\(durationMinutes) min")
            }
            if let side {
                parts.append(side.title)
            }
            return parts.isEmpty ? "Nursed" : parts.joined(separator: " · ")
        }
    }
}

extension FeedEntry: BabyScopedRow {}
