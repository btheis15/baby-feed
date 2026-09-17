import Foundation
import Testing
@testable import BabyFeed

struct IntakeGuidanceTests {
    private let ml = 1.0

    /// The question this whole file exists to answer: 30 ml logged against a
    /// 70 ml recommendation. It must come back as a normal smaller feed with
    /// reassurance, never as a problem.
    @Test func thirtyAgainstSeventyIsASmallerFeedNotAFailure() throws {
        let comparison = try #require(IntakeGuidance.compare(loggedML: 30, recommendedML: 70))
        #expect(comparison == .smaller)

        let note = try #require(IntakeGuidance.note(for: comparison, babyName: "Sam"))
        // It must reframe onto the day's total and say not to push.
        #expect(note.lowercased().contains("24 hours"))
        #expect(note.lowercased().contains("normal"))
        #expect(note.contains("Sam"))
        // And it must not describe a normal feed in alarming terms.
        for scary in ["concern", "worry", "problem", "too little", "not enough"] {
            #expect(!note.lowercased().contains(scary), "note should not say \(scary)")
        }
    }

    @Test func nearTheRecommendationSaysNothing() throws {
        let comparison = try #require(IntakeGuidance.compare(loggedML: 70, recommendedML: 70))
        #expect(comparison == .aboutRight)
        #expect(IntakeGuidance.note(for: .aboutRight, babyName: "Sam") == nil)

        // The band is wide enough that ordinary variation is silent.
        #expect(IntakeGuidance.compare(loggedML: 50, recommendedML: 70) == .aboutRight)
        #expect(IntakeGuidance.compare(loggedML: 90, recommendedML: 70) == .aboutRight)
    }

    @Test func thresholdsSitWhereTheDocumentationSays() {
        // Against 70 ml the boundaries are 0.6 × 70 = 42 and 1.4 × 70 = 98.
        #expect(IntakeGuidance.compare(loggedML: 42, recommendedML: 70) == .aboutRight)
        #expect(IntakeGuidance.compare(loggedML: 41.9, recommendedML: 70) == .smaller)
        #expect(IntakeGuidance.compare(loggedML: 20, recommendedML: 70) == .smaller)

        #expect(IntakeGuidance.compare(loggedML: 98, recommendedML: 70) == .aboutRight)
        #expect(IntakeGuidance.compare(loggedML: 98.1, recommendedML: 70) == .larger)
        #expect(IntakeGuidance.compare(loggedML: 120, recommendedML: 70) == .larger)
    }

    @Test func aLargerFeedIsAlsoReassuredNotFlagged() throws {
        let comparison = try #require(IntakeGuidance.compare(loggedML: 150, recommendedML: 70))
        #expect(comparison == .larger)
        let note = try #require(IntakeGuidance.note(for: comparison, babyName: "Sam"))
        #expect(note.lowercased().contains("normal"))
        #expect(note.lowercased().contains("cues"))
    }

    @Test func withoutARecommendationThereIsNothingToCompare() {
        #expect(IntakeGuidance.compare(loggedML: 30, recommendedML: nil) == nil)
        #expect(IntakeGuidance.compare(loggedML: 30, recommendedML: 0) == nil)
        // A zero-amount bottle isn't a feed yet.
        #expect(IntakeGuidance.compare(loggedML: 0, recommendedML: 70) == nil)
    }

    @Test func diaperExpectationsFollowTheFirstWeek() {
        #expect(IntakeGuidance.diaperExpectation(ageDays: 0)?.contains("1–2") == true)
        #expect(IntakeGuidance.diaperExpectation(ageDays: 3)?.contains("2–3") == true)
        #expect(IntakeGuidance.diaperExpectation(ageDays: 10)?.contains("5–6") == true)
        #expect(IntakeGuidance.diaperExpectation(ageDays: nil) == nil)
        #expect(IntakeGuidance.diaperExpectation(ageDays: -1) == nil)
    }

    @Test func redFlagsAreSplitByUrgencyAndNoneIsASmallFeed() {
        let urgent = IntakeGuidance.redFlags.filter { $0.urgency == .now }
        let soon = IntakeGuidance.redFlags.filter { $0.urgency == .soon }
        #expect(!urgent.isEmpty)
        #expect(!soon.isEmpty)
        #expect(urgent.count + soon.count == IntakeGuidance.redFlags.count)

        // A small feed must never be listed as a reason to call – that's the
        // misconception this screen exists to correct.
        let all = IntakeGuidance.redFlags.map(\.text.localizedLowercase).joined(separator: " ")
        #expect(!all.contains("small feed"))
        #expect(!all.contains("finish the bottle"))

        // The ones that genuinely matter are present.
        #expect(all.contains("wet diaper"))
        #expect(all.contains("birth weight"))
    }

    @Test func idsAreUniqueSoForEachIsStable() {
        let signalIDs = IntakeGuidance.whatMatters.map(\.id)
        #expect(Set(signalIDs).count == signalIDs.count)
        let flagIDs = IntakeGuidance.redFlags.map(\.id)
        #expect(Set(flagIDs).count == flagIDs.count)
    }

    @Test func theDayTotalIsListedBeforeAnythingElse() {
        // The whole point is reframing away from the single feed, so the
        // 24-hour total has to lead.
        #expect(IntakeGuidance.whatMatters.first?.id == "day-total")
    }

    @Test func everySourceItCitesExistsAndIsReputable() {
        #expect(!IntakeGuidance.sourceIDs.isEmpty)
        for id in IntakeGuidance.sourceIDs {
            let source = FoodGuidance.source(id)
            #expect(source != nil, "IntakeGuidance cites unknown source \(id)")
            let host = source?.url.host() ?? ""
            #expect(
                host.hasSuffix("aap.org") || host.hasSuffix("healthychildren.org") || host.hasSuffix("cdc.gov"),
                "\(id) points at \(host)"
            )
        }
    }

    @Test func theReassuringLinesAreActuallyPresent() {
        #expect(IntakeGuidance.bottomLine.lowercased().contains("right amount for them"))
        #expect(IntakeGuidance.diaperCaveat.lowercased().contains("weight check"))
    }
}
