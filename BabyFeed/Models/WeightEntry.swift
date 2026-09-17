import Foundation
import SwiftData

/// One weigh-in. Stored in grams; displayed in lb/oz or kg.
@Model
final class WeightEntry {
    var uuid: UUID?
    var babyID: UUID?
    var date: Date = Date()
    var grams: Double = 0
    var note: String = ""
    var loggedByName: String = ""
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var needsUpload: Bool = true

    init(uuid: UUID = UUID(), babyID: UUID? = nil, date: Date = .now, grams: Double, note: String = "", loggedByName: String = "") {
        self.uuid = uuid
        self.babyID = babyID
        self.date = date
        self.grams = grams
        self.note = note
        self.loggedByName = loggedByName
        self.updatedAt = .now
        self.needsUpload = true
    }

    var isActive: Bool { deletedAt == nil }

    func markChanged() {
        updatedAt = .now
        needsUpload = true
    }

    func softDelete() {
        deletedAt = .now
        markChanged()
    }
}

extension Array where Element == WeightEntry {
    func active(for babyID: UUID?) -> [WeightEntry] {
        filter { $0.deletedAt == nil && (babyID == nil || $0.babyID == babyID) }
    }
}
