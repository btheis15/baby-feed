import Foundation
import SwiftData

/// One weigh-in. Stored in grams; displayed in lb/oz or kg.
@Model
final class WeightEntry {
    var date: Date = Date()
    var grams: Double = 0
    var note: String = ""

    init(date: Date = .now, grams: Double, note: String = "") {
        self.date = date
        self.grams = grams
        self.note = note
    }
}
