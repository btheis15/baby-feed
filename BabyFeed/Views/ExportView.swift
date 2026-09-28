import SwiftData
import SwiftUI

/// The log as spreadsheets: everything in one file, or just the feeds.
///
/// Its own screen so the files are built once, when someone asks for them,
/// rather than on every redraw of Settings.
struct ExportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""
    @AppStorage(BabyProfile.nameKey) private var babyName = ""

    private struct Files {
        let everything: CSVFile
        let entryCount: Int
        let feeds: CSVFile
        let feedCount: Int
    }

    @State private var files: Files?

    var body: some View {
        List {
            if let files {
                Section {
                    ShareLink(item: files.everything, preview: SharePreview(files.everything.name)) {
                        Label("Everything", systemImage: "square.and.arrow.up")
                    }
                    .disabled(files.entryCount == 0)
                } footer: {
                    Text(files.entryCount == 0
                         ? "Nothing logged yet."
                         : "\(files.entryCount) entries: every feed, diaper, food, weight and note, one row each, with when it happened and who logged it.")
                }

                Section {
                    ShareLink(item: files.feeds, preview: SharePreview(files.feeds.name)) {
                        Label("Feeds only", systemImage: "square.and.arrow.up")
                    }
                    .disabled(files.feedCount == 0)
                } footer: {
                    Text(files.feedCount == 0
                         ? "No feeds logged yet."
                         : "\(files.feedCount) feeds, with amounts and minutes in columns of their own, for adding up in a spreadsheet.")
                }

                Section {
                } footer: {
                    Text("For the pediatrician, the stethoscope on the Timeline has a summary that reads better than a spreadsheet.")
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .task { files = build() }
    }

    private func build() -> Files {
        let id = UUID(uuidString: currentBabyIDRaw)
        func all<T: PersistentModel & CareEntry>(_ predicate: Predicate<T>) -> [T] {
            (try? modelContext.fetch(FetchDescriptor<T>(predicate: predicate))) ?? []
        }
        let sources = TimelineSources(
            feeds: all(#Predicate<FeedEntry> { $0.babyID == id && $0.deletedAt == nil }),
            diapers: all(#Predicate<DiaperEntry> { $0.babyID == id && $0.deletedAt == nil }),
            foods: all(#Predicate<SolidFoodEntry> { $0.babyID == id && $0.deletedAt == nil }),
            weights: all(#Predicate<WeightEntry> { $0.babyID == id && $0.deletedAt == nil }),
            notes: all(#Predicate<CareNote> { $0.babyID == id && $0.deletedAt == nil })
        )
        let unit = VolumeUnit(rawValue: unitRaw) ?? .ounces
        let items = TimelineBuilder.items(sources, babyID: id)
        let stamp = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day())
        let name = babyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = name.isEmpty ? "Baby Feed" : "\(name)"
        return Files(
            everything: CSVFile(
                name: "\(prefix) log \(stamp).csv",
                text: CareLogCSV.csv(items, unit: unit, weightUnit: WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces, calendar: calendar)
            ),
            entryCount: items.count,
            feeds: CSVFile(
                name: "\(prefix) feeds \(stamp).csv",
                text: FeedStats.csv(sources.feeds, unit: unit, calendar: calendar)
            ),
            feedCount: sources.feeds.count
        )
    }
}

#Preview {
    NavigationStack {
        ExportView()
    }
    .modelContainer(.preview)
}
