import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The whole log as one spreadsheet: every feed, diaper, food, weigh-in and
/// note, one row each, newest first, in the log's time zone.
///
/// The feeds-only export (`FeedStats.csv`) stays alongside it, because its
/// amounts and durations sit in columns of their own, which is what a
/// spreadsheet that adds up ounces needs.
enum CareLogCSV {
    static let header = "date,time,type,kind,details,note,logged_by"

    static func csv(_ items: [TimelineItem], unit: VolumeUnit, weightUnit: WeightUnit, calendar: Calendar) -> String {
        var lines = [header]
        for item in items.sorted(by: { $0.date > $1.date }) {
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let date = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            let row = fields(item, unit: unit, weightUnit: weightUnit)
            lines.append(([date, time] + [row.type, row.kind, row.details, row.note, item.entry.loggedByName].map(field))
                .joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func fields(_ item: TimelineItem, unit: VolumeUnit, weightUnit: WeightUnit)
        -> (type: String, kind: String, details: String, note: String) {
        switch item {
        case .feed(let feed):
            return ("feed", feed.kind.rawValue, feed.detailText(unit: unit), feed.note)
        case .diaper(let diaper):
            return ("diaper", diaper.kind.rawValue, "", diaper.note)
        case .food(let food, let isFirstTime):
            let details = [food.name, food.texture.title, food.reaction.title, isFirstTime ? "first time" : ""]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return ("food", food.texture.rawValue, details, food.note)
        case .weight(let weight):
            return ("weight", "", weightUnit.format(grams: weight.grams), weight.note)
        case .note(let note):
            return ("note", note.kind.rawValue, note.severity?.title ?? "", note.note)
        case .concern(let concern):
            let status = concern.resolvedAt.map { "resolved \(csvDate($0))" } ?? "ongoing"
            return ("concern", concern.kind.rawValue,
                    [concern.title, concern.severity?.title ?? "", status, concern.outcome]
                        .filter { !$0.isEmpty }.joined(separator: " · "),
                    concern.note)
        case .dose(let dose):
            return ("medicine", "", [dose.medicationName, dose.amountText ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                    dose.note)
        case .visit(let visit):
            return ("doctor visit", visit.kind.rawValue,
                    [visit.provider, visit.reason, visit.vaccines].filter { !$0.isEmpty }.joined(separator: " · "),
                    visit.doctorNotes)
        }
    }

    private static func csvDate(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: AppSettings.timeZone).year().month().day())
    }

    /// Quoted when it has to be, per RFC 4180: a comma, a quote or a line
    /// break inside a note would otherwise split it across columns or rows.
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// A CSV handed to the share sheet as a real .csv file, so it opens in Numbers
/// or Excel rather than arriving as a wall of text in a message.
struct CSVFile: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = URL.temporaryDirectory.appending(path: file.name)
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
