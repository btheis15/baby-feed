import Foundation

/// What every logged row has in common: which baby's log it belongs to, and
/// whether it has been soft-deleted.
///
/// Feeds, weights and care notes each carried their own identical copy of the
/// "undeleted rows for this baby" filter. One copy means a change to what
/// "active" means — a second kind of soft delete, say — can't reach two of the
/// three and leave the third quietly showing rows the others hide.
protocol BabyScopedRow {
    var babyID: UUID? { get }
    var deletedAt: Date? { get }
}

extension BabyScopedRow {
    /// Not soft-deleted, which is what every screen filters on.
    var isActive: Bool { deletedAt == nil }
}

extension Array where Element: BabyScopedRow {
    /// Undeleted rows for one baby, or for every baby when `babyID` is nil.
    func active(for babyID: UUID?) -> [Element] {
        filter { $0.deletedAt == nil && (babyID == nil || $0.babyID == babyID) }
    }
}
