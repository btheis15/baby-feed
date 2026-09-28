import Foundation
import SwiftData
import Testing
@testable import BabyFeed

@MainActor
struct BabyStoreTests {
    /// Removing a baby from this phone takes every one of its rows with it and
    /// leaves every other baby's alone. It used to forget diapers and solid
    /// foods, which lingered as orphans nothing could show or delete.
    @Test func removeLocallyDeletesEveryType() throws {
        let container = try AppSchema.inMemoryContainer()
        let context = container.mainContext

        let keep = Baby(name: "Keep", birthDate: nil)
        let gone = Baby(name: "Gone", birthDate: nil)
        context.insert(keep)
        context.insert(gone)
        for baby in [keep, gone] {
            context.insert(FeedEntry(babyID: baby.uuid, kind: .formula, amountML: 90))
            context.insert(WeightEntry(babyID: baby.uuid, grams: 3500))
            context.insert(CareNote(babyID: baby.uuid, kind: .other, note: "A note"))
            context.insert(DiaperEntry(babyID: baby.uuid, kind: .wet))
            context.insert(SolidFoodEntry(babyID: baby.uuid, name: "Avocado", texture: .puree))
        }
        try context.save()

        let keepID = keep.uuid
        let goneID = gone.uuid
        // Not the baby on screen, so removing it doesn't switch babies — which
        // would reach the widget, the reminder and the Live Activity from a test.
        #expect(AppSettings.currentBabyID != goneID)

        BabyStore.removeLocally(gone, in: context)

        func rowCounts(for babyID: UUID) throws -> [String: Int] {
            [
                "feeds": try context.fetch(FetchDescriptor<FeedEntry>()).filter { $0.babyID == babyID }.count,
                "weights": try context.fetch(FetchDescriptor<WeightEntry>()).filter { $0.babyID == babyID }.count,
                "notes": try context.fetch(FetchDescriptor<CareNote>()).filter { $0.babyID == babyID }.count,
                "diapers": try context.fetch(FetchDescriptor<DiaperEntry>()).filter { $0.babyID == babyID }.count,
                "foods": try context.fetch(FetchDescriptor<SolidFoodEntry>()).filter { $0.babyID == babyID }.count,
            ]
        }

        #expect(try rowCounts(for: goneID) == ["feeds": 0, "weights": 0, "notes": 0, "diapers": 0, "foods": 0])
        #expect(try rowCounts(for: keepID) == ["feeds": 1, "weights": 1, "notes": 1, "diapers": 1, "foods": 1])
        #expect(BabyStore.baby(withID: goneID, in: context) == nil)
        #expect(BabyStore.baby(withID: keepID, in: context) != nil)
    }

    /// Tests lean on each in-memory store starting empty. Two of them in one
    /// process must never see each other's rows.
    @Test func inMemoryContainersDoNotShareRows() throws {
        let first = try AppSchema.inMemoryContainer()
        let second = try AppSchema.inMemoryContainer()
        first.mainContext.insert(Baby(name: "Only in the first", birthDate: nil))
        first.mainContext.insert(DiaperEntry(kind: .both))
        try first.mainContext.save()

        #expect(try first.mainContext.fetch(FetchDescriptor<Baby>()).count == 1)
        #expect(try first.mainContext.fetch(FetchDescriptor<DiaperEntry>()).count == 1)
        #expect(try second.mainContext.fetch(FetchDescriptor<Baby>()).isEmpty)
        #expect(try second.mainContext.fetch(FetchDescriptor<DiaperEntry>()).isEmpty)
    }
}
