import Foundation
import SwiftData

/// Anything worth telling the pediatrician that isn't a feed or a weight –
/// breathing that sounded odd, a long crying spell, a rash, a bad night.
///
/// The point is the appointment: by the time you're in the room you won't
/// remember what happened eleven days ago, and "she was fussy for two days
/// around the 9th" is exactly the kind of thing a doctor wants.
///
/// Sync fields mirror `FeedEntry`: `uuid` identifies the row across devices,
/// `babyID` says whose log it is, `updatedAt` decides conflicts, `deletedAt` is
/// a soft delete, `needsUpload` queues the next push.
@Model
final class CareNote {
    var uuid: UUID?
    var babyID: UUID?
    var date: Date = Date()
    var kindRaw: String = CareNoteKind.other.rawValue
    /// What happened, in the caregiver's words. The whole value of the feature.
    var note: String = ""
    /// Optional 1–3 severity, for the kinds where "how bad" is the question.
    var severityRaw: Int?
    /// Set when it's still going on, so the report can say "ongoing".
    var resolvedAt: Date?
    var loggedByName: String = ""
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var needsUpload: Bool = true

    init(
        uuid: UUID = UUID(),
        babyID: UUID? = nil,
        date: Date = .now,
        kind: CareNoteKind,
        note: String = "",
        severity: CareNoteSeverity? = nil,
        loggedByName: String = ""
    ) {
        self.uuid = uuid
        self.babyID = babyID
        self.date = date
        self.kindRaw = kind.rawValue
        self.note = note
        self.severityRaw = severity?.rawValue
        self.loggedByName = loggedByName
        self.updatedAt = .now
        self.needsUpload = true
    }

    var kind: CareNoteKind {
        get { CareNoteKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var severity: CareNoteSeverity? {
        get { severityRaw.flatMap(CareNoteSeverity.init(rawValue:)) }
        set { severityRaw = newValue?.rawValue }
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

/// The kinds worth having as buttons, so logging at 3 a.m. is one tap plus a
/// sentence. `other` exists because a fixed list never covers everything.
enum CareNoteKind: String, CaseIterable, Identifiable, Codable {
    case breathing
    case crying
    case spitUp
    case stool
    case rash
    case temperature
    case sleep
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breathing: "Breathing"
        case .crying: "Crying"
        case .spitUp: "Spit up"
        case .stool: "Stool"
        case .rash: "Skin or rash"
        case .temperature: "Temperature"
        case .sleep: "Sleep"
        case .other: "Something else"
        }
    }

    var systemImage: String {
        switch self {
        case .breathing: "lungs.fill"
        case .crying: "face.dashed.fill"
        case .spitUp: "drop.triangle.fill"
        case .stool: "toilet.fill"
        case .rash: "allergens.fill"
        case .temperature: "thermometer.medium"
        case .sleep: "moon.zzz.fill"
        case .other: "square.and.pencil"
        }
    }

    /// A hint in the text field, so people know the kind of detail that helps a
    /// doctor rather than staring at an empty box.
    var placeholder: String {
        switch self {
        case .breathing: "Sounded snuffly for about 10 minutes after the feed…"
        case .crying: "Inconsolable for an hour around 8pm, settled after a burp…"
        case .spitUp: "Bigger than usual, right after a full bottle…"
        case .stool: "Very hard, seemed uncomfortable…"
        case .rash: "Red patches on both cheeks, not bothering her…"
        case .temperature: "37.9 °C under the arm, otherwise herself…"
        case .sleep: "Woke every 40 minutes all night…"
        case .other: "What happened, and anything that seemed to help…"
        }
    }

    /// Only some kinds have a meaningful "how bad was it".
    var usesSeverity: Bool {
        switch self {
        case .breathing, .crying, .spitUp, .rash, .sleep: true
        case .stool, .temperature, .other: false
        }
    }
}

enum CareNoteSeverity: Int, CaseIterable, Identifiable, Codable {
    case mild = 1
    case moderate = 2
    case severe = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .severe: "Severe"
        }
    }
}

extension CareNote: BabyScopedRow {}
