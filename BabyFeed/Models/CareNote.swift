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
    /// Not used, and never read as "ongoing": a note is a moment, and
    /// something that goes on is a `HealthConcern`. Kept, and still synced,
    /// only so a value an older build wrote isn't lost on the way through.
    var resolvedAt: Date?
    /// The concern this note is an update on ("less red today"), if any.
    var concernID: UUID?
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

/// The kinds worth having as buttons, so logging at 3 a.m. is one tap plus a
/// sentence. `other` exists because a fixed list never covers everything.
enum CareNoteKind: String, CaseIterable, Identifiable, Codable {
    case breathing
    case cough
    case eye
    case jaundice
    case cord
    case spitUp
    case vomiting
    case stool
    case rash
    case temperature
    case crying
    case sleep
    case teething
    case injury
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breathing: "Breathing"
        case .cough: "Cough or congestion"
        case .eye: "Eye — redness or discharge"
        case .jaundice: "Yellow skin or eyes"
        case .cord: "Umbilical cord"
        case .spitUp: "Spit up"
        case .vomiting: "Vomiting"
        // Not "Stool": the Dirty button logs those. This is the worry.
        case .stool: "Poop concern"
        case .rash: "Skin or rash"
        case .temperature: "Temperature"
        case .crying: "Crying"
        case .sleep: "Sleep"
        case .teething: "Teething"
        case .injury: "Bump or injury"
        case .other: "Something else"
        }
    }

    /// A short name for a concern's title: "Red eye", not the whole kind.
    var concernTitle: String {
        switch self {
        case .breathing: "Breathing"
        case .cough: "Cough"
        case .eye: "Red eye"
        case .jaundice: "Jaundice"
        case .cord: "Umbilical cord"
        case .spitUp: "Spitting up"
        case .vomiting: "Vomiting"
        case .stool: "Poop concern"
        case .rash: "Rash"
        case .temperature: "Temperature"
        case .crying: "Crying"
        case .sleep: "Sleep"
        case .teething: "Teething"
        case .injury: "Bump"
        case .other: ""
        }
    }

    var systemImage: String {
        switch self {
        case .breathing: "lungs.fill"
        case .cough: "wind"
        case .eye: "eye.fill"
        case .jaundice: "sun.max.fill"
        case .cord: "circle.dotted"
        case .spitUp: "drop.triangle.fill"
        case .vomiting: "exclamationmark.triangle.fill"
        case .stool: "toilet.fill"
        case .rash: "allergens.fill"
        case .temperature: "thermometer.medium"
        case .crying: "face.dashed.fill"
        case .sleep: "moon.zzz.fill"
        case .teething: "mouth.fill"
        case .injury: "bandage.fill"
        case .other: "square.and.pencil"
        }
    }

    /// A hint in the text field, so people know the kind of detail that helps a
    /// doctor rather than staring at an empty box.
    var placeholder: String {
        switch self {
        case .breathing: "Sounded snuffly for about 10 minutes after the feed…"
        case .cough: "Stuffy nose since yesterday, coughs after feeds…"
        case .eye: "Left eye red and goopy in the morning, wiped clean…"
        case .jaundice: "Face looks more yellow than yesterday…"
        case .cord: "A little bleeding where it came off, smells fine…"
        case .spitUp: "Bigger than usual, right after a full bottle…"
        case .vomiting: "Forceful, twice after the morning feed…"
        case .stool: "Very hard, seemed uncomfortable…"
        case .rash: "Red patches on both cheeks, not bothering her…"
        case .temperature: "37.9 °C under the arm, otherwise herself…"
        case .crying: "Inconsolable for an hour around 8pm, settled after a burp…"
        case .sleep: "Woke every 40 minutes all night…"
        case .teething: "Drooling a lot, chewing everything…"
        case .injury: "Rolled off the changing mat, cried straight away…"
        case .other: "What happened, and anything that seemed to help…"
        }
    }

    /// Only some kinds have a meaningful "how bad was it".
    var usesSeverity: Bool {
        switch self {
        case .breathing, .cough, .eye, .crying, .spitUp, .vomiting, .rash, .sleep, .teething, .injury: true
        case .jaundice, .cord, .stool, .temperature, .other: false
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
