import Foundation
import SwiftData
import SwiftUI

/// One diaper change. The highest-frequency thing anybody logs, so the entry
/// path is a single tap — there's no amount to type and no decision to make
/// beyond wet, dirty or both.
///
/// It earns its place next to feeds because the count is a medical signal:
/// wet diapers per day are how you and the pediatrician judge whether a baby
/// who can't be measured is getting enough.
///
/// Sync fields mirror `FeedEntry`: `uuid` identifies the row across devices,
/// `babyID` says whose log it is, `updatedAt` decides conflicts, `deletedAt` is
/// a soft delete, `needsUpload` queues the next push.
@Model
final class DiaperEntry {
    var uuid: UUID?
    var babyID: UUID?
    var time: Date = Date()
    var kindRaw: String = DiaperKind.wet.rawValue
    var note: String = ""
    var loggedByName: String = ""
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var needsUpload: Bool = true

    init(
        uuid: UUID = UUID(),
        babyID: UUID? = nil,
        time: Date = .now,
        kind: DiaperKind,
        note: String = "",
        loggedByName: String = ""
    ) {
        self.uuid = uuid
        self.babyID = babyID
        self.time = time
        self.kindRaw = kind.rawValue
        self.note = note
        self.loggedByName = loggedByName
        self.updatedAt = .now
        self.needsUpload = true
    }

    var kind: DiaperKind {
        get { DiaperKind(rawValue: kindRaw) ?? .wet }
        set { kindRaw = newValue.rawValue }
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

/// Wet, dirty, or both at once — `both` exists so one change is one row, not
/// two taps and a double-counted total.
enum DiaperKind: String, CaseIterable, Identifiable, Codable {
    case wet
    case dirty
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wet: "Wet"
        case .dirty: "Dirty"
        case .both: "Both"
        }
    }

    var systemImage: String {
        switch self {
        case .wet: "drop.halffull"
        case .dirty: "cloud.fill"
        case .both: "circle.lefthalf.filled"
        }
    }

    var color: Color {
        switch self {
        case .wet: .teal
        case .dirty: Color(red: 0.63, green: 0.44, blue: 0.28)
        case .both: .indigo
        }
    }

    /// Whether this change counts toward each tally. `both` counts as one wet
    /// and one dirty, which is what it was.
    var countsAsWet: Bool { self != .dirty }
    var countsAsDirty: Bool { self != .wet }
}

/// The two numbers the day is judged by.
struct DiaperTally {
    var wet = 0
    var dirty = 0

    var changeCount: Int { max(wet, dirty) == 0 ? 0 : wet + dirty }
    var isEmpty: Bool { wet == 0 && dirty == 0 }

    init(_ entries: [DiaperEntry]) {
        for entry in entries where entry.deletedAt == nil {
            if entry.kind.countsAsWet { wet += 1 }
            if entry.kind.countsAsDirty { dirty += 1 }
        }
    }

    /// "3 wet · 2 dirty", or just the side that happened.
    var text: String {
        var parts: [String] = []
        if wet > 0 { parts.append("\(wet) wet") }
        if dirty > 0 { parts.append("\(dirty) dirty") }
        return parts.isEmpty ? "None yet" : parts.joined(separator: " · ")
    }
}

extension Array where Element == DiaperEntry {
    func active(for babyID: UUID?) -> [DiaperEntry] {
        filter { $0.deletedAt == nil && (babyID == nil || $0.babyID == babyID) }
    }

    func within(_ interval: TimeInterval, now: Date = .now) -> [DiaperEntry] {
        filter { now.timeIntervalSince($0.time) <= interval && $0.time <= now }
    }
}
