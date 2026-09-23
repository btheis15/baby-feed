import Foundation
import Testing
@testable import BabyFeed

/// Solid foods: the age gate, the first-time check that makes allergen tracing
/// possible, and the report the pediatrician reads.
struct SolidFoodTests {
    // MARK: The gate

    /// The requirement, pinned: options exist only in the ranges the AAP
    /// recommends. These numbers must be the FoodGuidance stage boundaries —
    /// if either side moves, this fails rather than the two screens drifting.
    @Test func texturesUnlockOnTheAAPStageBoundaries() {
        #expect(FoodTexture.available(atMonths: 0).isEmpty, "milk only — no solids UI at all")
        #expect(FoodTexture.available(atMonths: 3).isEmpty)

        #expect(FoodTexture.available(atMonths: 4) == [.puree],
                "possible from 4 months with readiness, per the AAP")
        #expect(FoodTexture.available(atMonths: 5) == [.puree])

        #expect(FoodTexture.available(atMonths: 6) == [.puree, .mashed], "first foods")
        #expect(FoodTexture.available(atMonths: 8) == [.puree, .mashed])

        #expect(FoodTexture.available(atMonths: 9) == [.puree, .mashed, .fingerFood], "more texture")

        #expect(FoodTexture.available(atMonths: 12) == FoodTexture.allCases, "family food")
        #expect(FoodTexture.available(atMonths: 24) == FoodTexture.allCases)
    }

    /// Each unlock age must sit inside the stage whose advice it came from, so
    /// a future edit to the stages can't orphan a texture.
    @Test func everyTextureBelongsToItsStage() {
        #expect(FoodGuidance.stage(forMonths: FoodTexture.puree.availableFromMonths).id == "watch-for-readiness")
        #expect(FoodGuidance.stage(forMonths: FoodTexture.mashed.availableFromMonths).id == "first-foods")
        #expect(FoodGuidance.stage(forMonths: FoodTexture.fingerFood.availableFromMonths).id == "more-texture")
        #expect(FoodGuidance.stage(forMonths: FoodTexture.familyFood.availableFromMonths).id == "toddler")
    }

    // MARK: First time

    @Test func firstTimeIgnoresCapitalisationAndSpaces() {
        let babyID = UUID()
        let earlier = SolidFoodEntry(babyID: babyID, time: .now.addingTimeInterval(-86400),
                                     name: "Sweet Potato", texture: .puree)
        let later = SolidFoodEntry(babyID: babyID, time: .now,
                                   name: " sweet potato ", texture: .mashed)
        let log = [earlier, later]

        #expect(log.isFirstTime(earlier), "the earliest entry of a food is its first time")
        #expect(!log.isFirstTime(later), "however it was typed, it's the same food")
    }

    @Test func aDeletedEarlierTasteDoesNotStealFirstTime() {
        let babyID = UUID()
        let deleted = SolidFoodEntry(babyID: babyID, time: .now.addingTimeInterval(-86400),
                                     name: "Egg", texture: .puree)
        deleted.softDelete()
        let real = SolidFoodEntry(babyID: babyID, time: .now, name: "Egg", texture: .puree)

        #expect([deleted, real].isFirstTime(real))
    }

    @Test func suggestionsAreDistinctAndNewestFirst() {
        let babyID = UUID()
        let log = [
            SolidFoodEntry(babyID: babyID, time: .now.addingTimeInterval(-300), name: "Avocado", texture: .puree),
            SolidFoodEntry(babyID: babyID, time: .now.addingTimeInterval(-200), name: "Oat cereal", texture: .puree),
            SolidFoodEntry(babyID: babyID, time: .now.addingTimeInterval(-100), name: "avocado", texture: .mashed),
        ]
        #expect(log.distinctNames == ["avocado", "Oat cereal"],
                "one entry per food, spelled the way it was logged last")
    }

    // MARK: Sync shape

    @Test func theDTORoundTripsEverything() {
        let entry = SolidFoodEntry(babyID: UUID(), time: .now.addingTimeInterval(-3600),
                                   name: "Peanut butter, thinned", texture: .puree,
                                   reaction: .possibleReaction, note: "small rash on chin",
                                   loggedByName: "Annette")
        let dto = SolidFoodDTO(entry: entry, userID: UUID())
        #expect(dto?.texture == "puree")
        #expect(dto?.reaction == "possibleReaction")

        let restored = SolidFoodEntry(uuid: dto!.id, name: "", texture: .mashed)
        dto!.apply(to: restored)
        #expect(restored.name == "Peanut butter, thinned")
        #expect(restored.reaction == .possibleReaction)
        #expect(restored.note == "small rash on chin")
        #expect(!restored.needsUpload)
    }

    @Test func aFoodWithoutABabyMakesNoDTO() {
        #expect(SolidFoodDTO(entry: SolidFoodEntry(name: "Pear", texture: .puree), userID: UUID()) == nil)
    }

    // MARK: The report

    @Test func theReportListsFoodsWithFirstTimesAndReactions() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
        let babyID = UUID()
        let feed = FeedEntry(babyID: babyID, startTime: now.addingTimeInterval(-600),
                             kind: .formula, amountML: 120)

        let foods = [
            // Tried long before the window: NOT a first time inside it.
            SolidFoodEntry(babyID: babyID, time: now.addingTimeInterval(-40 * 86400),
                           name: "Avocado", texture: .puree),
            SolidFoodEntry(babyID: babyID, time: now.addingTimeInterval(-3600),
                           name: "avocado", texture: .mashed),
            SolidFoodEntry(babyID: babyID, time: now.addingTimeInterval(-7200),
                           name: "Egg", texture: .puree, reaction: .possibleReaction),
        ]

        let report = DaySummaryGenerator.report(
            entries: [feed], weights: [], solidFoods: foods, days: 7,
            unit: .milliliters, weightUnit: .kilograms,
            profile: BabyProfile(name: "Nora", birthDate: nil, sex: .unspecified, dueDate: nil),
            calendar: calendar, now: now)

        #expect(report.foods.count == 2, "only the window's foods, not the whole history")

        let avocado = report.foods.first { $0.name == "avocado" }
        #expect(avocado?.isFirstTime == false, "first-time is judged against the whole log")

        let egg = report.foods.first { $0.name == "Egg" }
        #expect(egg?.isFirstTime == true)
        #expect(egg?.flagged == true)

        let text = DaySummaryGenerator.plainText(from: report)
        #expect(text.contains("Egg (first time): reaction?"))
        #expect(text.contains("Foods"))
    }

    @Test func aWindowWithoutFoodsSaysNothingAboutThem() {
        let report = DaySummaryGenerator.report(
            entries: [FeedEntry(kind: .formula)], weights: [], days: 7,
            unit: .milliliters, weightUnit: .kilograms,
            profile: BabyProfile(name: "Nora", birthDate: nil, sex: .unspecified, dueDate: nil))
        #expect(!report.hasFoods)
        #expect(!DaySummaryGenerator.plainText(from: report).contains("Foods"))
    }
}
