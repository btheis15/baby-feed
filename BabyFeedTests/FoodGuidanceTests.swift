import Foundation
import Testing
@testable import BabyFeed

struct FoodGuidanceTests {
    @Test func stagesCoverEveryMonthWithoutOverlapping() {
        for months in 0...36 {
            let matching = FoodGuidance.stages.filter { $0.contains(months: months) }
            #expect(matching.count == 1, "\(months) months matched \(matching.count) stages")
        }
        // Negative ages are clamped rather than crashing.
        #expect(FoodGuidance.stage(forMonths: -3).id == "milk-only")
    }

    @Test func stagesLandOnTheExpectedAges() {
        #expect(FoodGuidance.stage(forMonths: 0).id == "milk-only")
        #expect(FoodGuidance.stage(forMonths: 3).id == "milk-only")
        #expect(FoodGuidance.stage(forMonths: 4).id == "watch-for-readiness")
        #expect(FoodGuidance.stage(forMonths: 5).id == "watch-for-readiness")
        #expect(FoodGuidance.stage(forMonths: 6).id == "first-foods")
        #expect(FoodGuidance.stage(forMonths: 9).id == "more-texture")
        #expect(FoodGuidance.stage(forMonths: 12).id == "toddler")
        #expect(FoodGuidance.stage(forMonths: 30).id == "toddler")
    }

    /// The specific thresholds parents most need to be right.
    @Test func theHeadlineAgeLimitsMatchPublishedGuidance() throws {
        func rule(_ id: String) throws -> FoodGuidance.AvoidRule {
            try #require(FoodGuidance.avoidRules.first { $0.id == id })
        }

        // Honey: botulism risk until 12 months (CDC).
        #expect(try rule("honey").clearedAtMonths == 12)
        #expect(try rule("honey").applies(atMonths: 11))
        #expect(try !rule("honey").applies(atMonths: 12))

        // Cow's milk as a drink: not before 12 months (CDC).
        #expect(try rule("cows-milk").clearedAtMonths == 12)

        // No juice at all before 12 months (AAP).
        #expect(try rule("juice").clearedAtMonths == 12)

        // Water only from 6 months (CDC).
        #expect(try rule("water-early").clearedAtMonths == 6)
        #expect(try rule("water-early").applies(atMonths: 5))
        #expect(try !rule("water-early").applies(atMonths: 6))

        // No added sugar or caffeine before 24 months (CDC).
        #expect(try rule("added-sugar").clearedAtMonths == 24)
        #expect(try rule("caffeine").clearedAtMonths == 24)
    }

    @Test func permanentRulesNeverClear() {
        let alwaysOn = ["choking", "unpasteurized", "high-mercury-fish", "salt", "plant-milks", "cereal-in-bottle", "rice-only-cereal"]
        for id in alwaysOn {
            let rule = FoodGuidance.avoidRules.first { $0.id == id }
            #expect(rule?.clearedAtMonths == nil, "\(id) should apply at any age")
            #expect(rule?.applies(atMonths: 36) == true)
        }
    }

    @Test func applyingAndClearedRulesPartitionTheWholeSet() {
        for months in [0, 5, 6, 11, 12, 23, 24, 30] {
            let applying = FoodGuidance.rules(applyingAtMonths: months)
            let cleared = FoodGuidance.rules(clearedByMonths: months)
            #expect(applying.count + cleared.count == FoodGuidance.avoidRules.count)
            // No rule can be in both lists.
            let overlap = Set(applying.map(\.id)).intersection(cleared.map(\.id))
            #expect(overlap.isEmpty)
        }
    }

    @Test func newbornsHaveEverythingRestrictedAndToddlersLess() {
        let newborn = FoodGuidance.rules(applyingAtMonths: 0).count
        let toddler = FoodGuidance.rules(applyingAtMonths: 18).count
        #expect(newborn == FoodGuidance.avoidRules.count)
        #expect(toddler < newborn)
        // A 12-month-old has cleared honey, cow's milk, juice and water.
        #expect(FoodGuidance.rules(clearedByMonths: 12).count == 4)
    }

    @Test func safetyRulesAreListedFirst() {
        let rules = FoodGuidance.rules(applyingAtMonths: 0)
        let reasons = rules.map(\.reason)
        let firstNonSafety = reasons.firstIndex { $0 != .safety } ?? reasons.count
        // Nothing after the first non-safety entry may be a safety rule.
        #expect(!reasons[firstNonSafety...].contains(.safety))
    }

    /// Medical claims without a citation are the thing to avoid shipping.
    @Test func everyRuleAndStageCitesARealSource() {
        let known = Set(FoodGuidance.sources.map(\.id))
        #expect(!known.isEmpty)

        for rule in FoodGuidance.avoidRules {
            #expect(!rule.sourceIDs.isEmpty, "\(rule.id) has no source")
            for id in rule.sourceIDs {
                #expect(known.contains(id), "\(rule.id) cites unknown source \(id)")
            }
            #expect(!rule.detail.isEmpty)
        }

        for stage in FoodGuidance.stages {
            #expect(!stage.sourceIDs.isEmpty, "\(stage.id) has no source")
            for id in stage.sourceIDs {
                #expect(known.contains(id), "\(stage.id) cites unknown source \(id)")
            }
            #expect(!stage.canEat.isEmpty)
        }
    }

    @Test func sourcesAreUniqueAndPointAtTheRightOrganisations() {
        let ids = FoodGuidance.sources.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate source id")

        for source in FoodGuidance.sources {
            #expect(source.url.scheme == "https")
            let host = source.url.host() ?? ""
            #expect(
                host.hasSuffix("aap.org") || host.hasSuffix("healthychildren.org")
                    || host.hasSuffix("cdc.gov") || host.hasSuffix("who.int"),
                "\(source.id) points at \(host), which isn't AAP, CDC or WHO"
            )
        }
    }

    /// The emerging-evidence section is the one most able to do harm if it
    /// drifts, so it's pinned down: every topic must name real papers, and
    /// every paper must be reachable.
    @Test func everyEmergingTopicNamesRealCitations() {
        #expect(!FoodGuidance.emergingTopics.isEmpty)
        for topic in FoodGuidance.emergingTopics {
            #expect(!topic.citations.isEmpty, "\(topic.id) has no citation")
            #expect(!topic.question.isEmpty)
            // All three sides must be stated – current advice, the new evidence,
            // and why it isn't settled. A topic missing the catch is advocacy.
            #expect(!topic.established.isEmpty, "\(topic.id) omits current advice")
            #expect(!topic.emerging.isEmpty, "\(topic.id) omits the new evidence")
            #expect(!topic.limitation.isEmpty, "\(topic.id) omits the limitation")

            for citation in topic.citations {
                #expect(citation.url.scheme == "https")
                #expect(!citation.authors.isEmpty)
                #expect(!citation.title.isEmpty)
                // A named journal and year, so it can be looked up offline.
                #expect(citation.publication.contains("20"), "\(citation.title) has no year")
            }
        }
    }

    /// Checks the substance is present without pinning exact phrasing, so the
    /// wording can be edited without a false failure – but it can't quietly
    /// lose the three things it has to say.
    @Test func emergingDisclaimerSaysItIsNotAdvice() {
        let text = FoodGuidance.emergingDisclaimer.lowercased()
        #expect(text.contains("not the current us consensus"))
        #expect(text.contains("recommendation"))
        #expect(text.contains("pediatrician"))
        #expect(!text.isEmpty)
    }

    /// Known-dangerous practices must stay in the hard "avoid" list and must
    /// never appear as an open question.
    @Test func settledDangersAreNotPresentedAsOpenQuestions() {
        let emergingText = FoodGuidance.emergingTopics
            .flatMap { [$0.question, $0.established, $0.emerging] }
            .joined(separator: " ")
            .lowercased()

        // These are settled, not contested. They belong in avoidRules only.
        for dangerous in ["raw milk", "unpasteurized milk", "homemade formula", "goat milk formula"] {
            #expect(!emergingText.contains(dangerous), "\(dangerous) must not be framed as an open question")
        }

        // And honey's hard limit is still a rule, not a debate.
        let honey = FoodGuidance.avoidRules.first { $0.id == "honey" }
        #expect(honey?.clearedAtMonths == 12)
        #expect(!FoodGuidance.emergingTopics.contains { $0.id.contains("honey") })
    }

    @Test func monthsFromDaysUsesWholeMonths() {
        #expect(FoodGuidance.months(fromDays: 0) == 0)
        #expect(FoodGuidance.months(fromDays: 29) == 0)
        #expect(FoodGuidance.months(fromDays: 31) == 1)
        #expect(FoodGuidance.months(fromDays: 182) == 5)
        #expect(FoodGuidance.months(fromDays: 183) == 6)
        #expect(FoodGuidance.months(fromDays: 365) == 11)
        #expect(FoodGuidance.months(fromDays: 366) == 12)
        #expect(FoodGuidance.months(fromDays: -10) == 0)
    }
}
