import Foundation

/// What every row in the log has in common, whatever it records.
///
/// The stored date properties keep their own names — a feed's `startTime`, a
/// diaper's `time`, a weigh-in's `date` — because the SwiftData store, the sync
/// DTOs and the predicates all use them. `occurredAt` is the one name the
/// timeline and the day grouping read.
protocol CareEntry: AnyObject {
    var uuid: UUID? { get }
    var babyID: UUID? { get }
    var deletedAt: Date? { get set }
    var loggedByName: String { get }
    var occurredAt: Date { get }
    func markChanged()
    func softDelete()
}

extension CareEntry {
    /// Brings back a row that was just deleted — the Undo on the toast. The
    /// row is queued again, so the undelete reaches the other phone the same
    /// way the delete did.
    func restore() {
        deletedAt = nil
        markChanged()
    }
}

extension FeedEntry: CareEntry {
    var occurredAt: Date { startTime }
}

extension DiaperEntry: CareEntry {
    var occurredAt: Date { time }
}

extension SolidFoodEntry: CareEntry {
    var occurredAt: Date { time }
}

extension WeightEntry: CareEntry {
    var occurredAt: Date { date }
}

extension CareNote: CareEntry {
    var occurredAt: Date { date }
}

extension Array where Element: CareEntry {
    /// Undeleted rows for one baby (or for every baby when `babyID` is nil).
    func active(for babyID: UUID?) -> [Element] {
        filter { $0.deletedAt == nil && (babyID == nil || $0.babyID == babyID) }
    }
}

/// "Logged by Annette" — never "fed by": whoever had a free hand to tap Save
/// isn't necessarily whoever held the bottle. Nil when no name was set.
enum LoggedBy {
    static func text(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : "Logged by \(trimmed)"
    }
}
