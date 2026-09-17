import Foundation
import Testing
@testable import BabyFeed

/// Bottle amounts follow the guidance so they keep up with the baby, unless a
/// caregiver has pinned one by hand.
struct FeedDefaultsTests {
    /// A throwaway UserDefaults so these never touch the real ones.
    private func makeDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "FeedDefaultsTests.\(name)")!
        defaults.removePersistentDomain(forName: "FeedDefaultsTests.\(name)")
        return defaults
    }

    @Test func withNothingKnownItFallsBackToAPlainAmount() {
        let defaults = makeDefaults("empty")
        let ml = FeedDefaults.defaultAmountML(for: .formula, unit: .ounces, defaults: defaults)
        #expect(ml == VolumeUnit.ounces.toMilliliters(2))
        #expect(FeedDefaults.followsRecommendation(for: .formula, defaults: defaults))
    }

    @Test func theRecommendationIsUsedAndSnappedToTheUnitStep() {
        let defaults = makeDefaults("recommended")
        // 18.8 oz a day over 8 feeds is 2.35 oz – should read as 2.5, not 2.35.
        defaults.set(VolumeUnit.ounces.toMilliliters(2.35), forKey: FeedDefaults.recommendedPerFeedKey)

        let ml = FeedDefaults.defaultAmountML(for: .formula, unit: .ounces, defaults: defaults)
        let ounces = VolumeUnit.ounces.fromMilliliters(ml)
        #expect(abs(ounces - 2.5) < 0.001)
    }

    @Test func millilitresSnapToTheirOwnStep() {
        let defaults = makeDefaults("ml")
        defaults.set(69.0, forKey: FeedDefaults.recommendedPerFeedKey)
        // The ml step is 10, so 69 reads as 70.
        let ml = FeedDefaults.defaultAmountML(for: .formula, unit: .milliliters, defaults: defaults)
        #expect(abs(ml - 70) < 0.001)
    }

    @Test func aPinnedAmountBeatsTheRecommendation() {
        let defaults = makeDefaults("pinned")
        defaults.set(VolumeUnit.ounces.toMilliliters(2.5), forKey: FeedDefaults.recommendedPerFeedKey)
        FeedDefaults.setDefaultAmountML(VolumeUnit.ounces.toMilliliters(5), for: .formula, defaults: defaults)

        let ml = FeedDefaults.defaultAmountML(for: .formula, unit: .ounces, defaults: defaults)
        #expect(abs(VolumeUnit.ounces.fromMilliliters(ml) - 5) < 0.001)
        #expect(!FeedDefaults.followsRecommendation(for: .formula, defaults: defaults))

        // The other kind is untouched and still follows the recommendation.
        #expect(FeedDefaults.followsRecommendation(for: .breastMilk, defaults: defaults))
        let other = FeedDefaults.defaultAmountML(for: .breastMilk, unit: .ounces, defaults: defaults)
        #expect(abs(VolumeUnit.ounces.fromMilliliters(other) - 2.5) < 0.001)
    }

    @Test func unpinningGoesBackToTheRecommendation() {
        let defaults = makeDefaults("unpin")
        defaults.set(VolumeUnit.ounces.toMilliliters(3), forKey: FeedDefaults.recommendedPerFeedKey)
        FeedDefaults.setDefaultAmountML(VolumeUnit.ounces.toMilliliters(6), for: .formula, defaults: defaults)
        #expect(!FeedDefaults.followsRecommendation(for: .formula, defaults: defaults))

        FeedDefaults.setDefaultAmountML(nil, for: .formula, defaults: defaults)
        #expect(FeedDefaults.followsRecommendation(for: .formula, defaults: defaults))
        let ml = FeedDefaults.defaultAmountML(for: .formula, unit: .ounces, defaults: defaults)
        #expect(abs(VolumeUnit.ounces.fromMilliliters(ml) - 3) < 0.001)
    }

    /// The recommendation moving is the whole point: the amount must follow it
    /// without anyone editing a setting.
    @Test func theAmountMovesWhenTheRecommendationDoes() {
        let defaults = makeDefaults("moves")

        defaults.set(VolumeUnit.ounces.toMilliliters(2), forKey: FeedDefaults.recommendedPerFeedKey)
        let newborn = FeedDefaults.defaultAmountML(for: .formula, unit: .ounces, defaults: defaults)

        // A month on, a heavier baby and fewer feeds a day.
        defaults.set(VolumeUnit.ounces.toMilliliters(4.5), forKey: FeedDefaults.recommendedPerFeedKey)
        let older = FeedDefaults.defaultAmountML(for: .formula, unit: .ounces, defaults: defaults)

        #expect(older > newborn)
        #expect(abs(VolumeUnit.ounces.fromMilliliters(older) - 4.5) < 0.001)
    }

    @Test func nursingStillRemembersWhatYouDidLast() {
        let defaults = makeDefaults("nursing")
        // There's no weight-based rule for how long a session should last, so
        // this one legitimately stays a last-used value.
        #expect(FeedDefaults.defaultNursingMinutes(defaults: defaults) == 15)
        FeedDefaults.setDefaultNursingMinutes(22, defaults: defaults)
        #expect(FeedDefaults.defaultNursingMinutes(defaults: defaults) == 22)
    }
}

/// The reminder interval follows the baby's age unless pinned, so the gap
/// widens on its own instead of staying where it was set in week one.
struct ReminderIntervalTests {
    @Test func zeroMeansFollowTheAgeTypicalInterval() {
        #expect(AppSettings.resolvedIntervalMinutes(raw: 0) == AppSettings.suggestedIntervalMinutes)
    }

    @Test func aPinnedIntervalIsHonoured() {
        #expect(AppSettings.resolvedIntervalMinutes(raw: 240) == 240)
        #expect(AppSettings.resolvedIntervalMinutes(raw: 120) == 120)
    }

    @Test func theSuggestionIsAlwaysOneOfTheOfferedChoices() {
        #expect(AppSettings.intervalChoices.contains(AppSettings.suggestedIntervalMinutes))
    }

    /// The underlying rule widens with age; this is what makes "typical for
    /// age" worth following rather than pinning.
    @Test func theUnderlyingRuleWidensWithAge() {
        let newborn = FeedingGuidance.suggestedIntervalHours(ageDays: 2)
        let sixMonths = FeedingGuidance.suggestedIntervalHours(ageDays: 190)
        #expect(sixMonths > newborn)
    }
}

/// Amounts written by the old "each feed becomes the next default" behaviour
/// must not be mistaken for deliberate pins.
struct LegacyPinMigrationTests {
    private func makeDefaults(_ name: String) -> UserDefaults {
        let suite = "LegacyPinMigrationTests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func legacyAmountsAreClearedOnceSoTheRecommendationTakesOver() {
        let defaults = makeDefaults("clears")
        // What the old behaviour would have left after logging a 4 oz bottle.
        defaults.set(VolumeUnit.ounces.toMilliliters(4), forKey: FeedDefaults.amountKey(for: .formula))
        defaults.set(VolumeUnit.ounces.toMilliliters(2), forKey: FeedDefaults.amountKey(for: .breastMilk))
        defaults.set(VolumeUnit.ounces.toMilliliters(2.5), forKey: FeedDefaults.recommendedPerFeedKey)

        FeedDefaults.clearLegacyPinsIfNeeded(defaults: defaults)

        #expect(FeedDefaults.followsRecommendation(for: .formula, defaults: defaults))
        #expect(FeedDefaults.followsRecommendation(for: .breastMilk, defaults: defaults))
        let ml = FeedDefaults.defaultAmountML(for: .formula, unit: .ounces, defaults: defaults)
        #expect(abs(VolumeUnit.ounces.fromMilliliters(ml) - 2.5) < 0.001)
    }

    @Test func aPinSetAfterTheMigrationSurvives() {
        let defaults = makeDefaults("survives")
        FeedDefaults.clearLegacyPinsIfNeeded(defaults: defaults)

        // The caregiver deliberately pins one in Settings afterwards.
        FeedDefaults.setDefaultAmountML(VolumeUnit.ounces.toMilliliters(5), for: .formula, defaults: defaults)

        // Running again must not wipe it - the migration is once only.
        FeedDefaults.clearLegacyPinsIfNeeded(defaults: defaults)
        #expect(!FeedDefaults.followsRecommendation(for: .formula, defaults: defaults))
        let ml = FeedDefaults.defaultAmountML(for: .formula, unit: .ounces, defaults: defaults)
        #expect(abs(VolumeUnit.ounces.fromMilliliters(ml) - 5) < 0.001)
    }

    @Test func nursingMinutesAreNotTouched() {
        let defaults = makeDefaults("nursing")
        FeedDefaults.setDefaultNursingMinutes(25, defaults: defaults)
        FeedDefaults.clearLegacyPinsIfNeeded(defaults: defaults)
        #expect(FeedDefaults.defaultNursingMinutes(defaults: defaults) == 25)
    }
}
