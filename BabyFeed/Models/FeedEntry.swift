import Foundation
import SwiftData

/// One feed. Bottle feeds carry a volume (always stored in ml);
/// nursing carries a duration and optionally a side.
@Model
final class FeedEntry {
    var startTime: Date = Date()
    var kindRaw: String = FeedKind.formula.rawValue
    var amountML: Double?
    var durationMinutes: Int?
    var sideRaw: String?
    var note: String = ""

    init(
        startTime: Date = .now,
        kind: FeedKind,
        amountML: Double? = nil,
        durationMinutes: Int? = nil,
        side: NursingSide? = nil,
        note: String = ""
    ) {
        self.startTime = startTime
        self.kindRaw = kind.rawValue
        self.amountML = amountML
        self.durationMinutes = durationMinutes
        self.sideRaw = side?.rawValue
        self.note = note
    }

    var kind: FeedKind {
        get { FeedKind(rawValue: kindRaw) ?? .formula }
        set { kindRaw = newValue.rawValue }
    }

    var side: NursingSide? {
        get { sideRaw.flatMap(NursingSide.init(rawValue:)) }
        set { sideRaw = newValue?.rawValue }
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
