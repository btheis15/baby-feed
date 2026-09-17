import Foundation

/// Why one feed's size doesn't mean much, what actually tells you a baby is
/// getting enough, and when it's worth a call.
///
/// This exists because the app now shows a recommended per-feed amount, and a
/// recommendation invites a parent to read a smaller feed as a failure. The
/// AAP's position is the opposite: babies self-regulate, feeds vary, and the
/// signals worth watching are the day's total, weight gain and nappies. Every
/// statement here traces to a source in `FoodGuidance.sources`.
enum IntakeGuidance {
    // MARK: A single feed against the recommendation

    /// How one feed compares with the recommended amount.
    ///
    /// Deliberately not "good" and "bad". A 30 ml feed against a 70 ml
    /// recommendation is a normal feed, not a shortfall.
    enum FeedComparison: Equatable {
        case aboutRight
        case smaller
        case larger
    }

    /// Below 60% or above 140% of the recommendation is far enough from it to
    /// be worth a word of context. Inside that, saying anything would be noise.
    static let smallerThreshold = 0.6
    static let largerThreshold = 1.4

    /// Nil when there's no recommendation to compare against, or the amount
    /// isn't a real feed yet.
    static func compare(loggedML: Double, recommendedML: Double?) -> FeedComparison? {
        guard let recommendedML, recommendedML > 0, loggedML > 0 else { return nil }
        let ratio = loggedML / recommendedML
        if ratio < smallerThreshold { return .smaller }
        if ratio > largerThreshold { return .larger }
        return .aboutRight
    }

    /// Context for a feed that's well away from the recommendation.
    ///
    /// Reassurance, never a warning – a single feed is not a problem, and the
    /// honest move is to point at the day's total instead. Nil for a feed near
    /// the recommendation, where there's nothing useful to add.
    static func note(for comparison: FeedComparison, babyName: String) -> String? {
        switch comparison {
        case .aboutRight:
            return nil
        case .smaller:
            return """
                That's a normal feed. Appetite swings through the day and some \
                feeds are just smaller – what counts is the total over 24 hours, \
                not any one bottle. Don't push \(babyName) to finish.
                """
        case .larger:
            return """
                Also normal – babies take more during a growth spurt. Follow \
                \(babyName)'s cues rather than the number, and stop when they \
                turn away or relax their hands.
                """
        }
    }

    // MARK: What actually tells you it's going well

    struct Signal: Identifiable, Equatable {
        let id: String
        let title: String
        let detail: String
    }

    /// The things that mean a baby is getting enough – in the order a tired
    /// parent should think about them.
    static let whatMatters: [Signal] = [
        Signal(
            id: "day-total",
            title: "The day's total, not one feed",
            detail: "Roughly 2½ oz (75 ml) per pound of body weight over 24 hours, and usually no more than about 32 oz (960 ml). Individual feeds vary a lot around that."
        ),
        Signal(
            id: "weight",
            title: "Weight gain",
            detail: "Losing up to 7–10% in the first days is expected, back to birth weight by about 10–14 days, then a steady climb. This is the measure your pediatrician trusts most."
        ),
        Signal(
            id: "nappies",
            title: "Wet diapers",
            detail: "2–3 a day in the first few days, then at least 5–6 a day once milk is in, with pale or nearly colourless urine."
        ),
        Signal(
            id: "stools",
            title: "Stools",
            detail: "Dark and tarry on days 1–2, turning greenish-yellow by days 3–4, then yellow and loose – at least 3–4 a day by the end of the first week."
        ),
        Signal(
            id: "contentment",
            title: "How they seem",
            detail: "Content after most feeds, waking to feed 8–12 times a day early on, and not spitting up excessively."
        ),
    ]

    /// What to expect from nappies at a given age, which changes fast in the
    /// first week. Nil without a birthday to work from.
    static func diaperExpectation(ageDays: Int?) -> String? {
        guard let ageDays, ageDays >= 0 else { return nil }
        if ageDays <= 1 { return "1–2 wet diapers a day is normal this early." }
        if ageDays < 5 { return "About 2–3 wet diapers a day while your milk comes in." }
        return "At least 5–6 wet diapers a day, and 3–4 stools."
    }

    // MARK: When to call

    enum Urgency: String, Equatable {
        /// Don't wait.
        case now = "Call right away"
        /// Same day, or the next appointment.
        case soon = "Worth a call today"
    }

    struct RedFlag: Identifiable, Equatable {
        let id: String
        let text: String
        let urgency: Urgency
    }

    /// The real red flags. Small feeds are not on this list; these are.
    static let redFlags: [RedFlag] = [
        RedFlag(
            id: "no-urine",
            text: "No wet diaper in more than 8 hours, or dark urine",
            urgency: .now
        ),
        RedFlag(
            id: "wont-feed",
            text: "Won't feed, or takes very little, for more than 8 hours",
            urgency: .now
        ),
        RedFlag(
            id: "dehydration",
            text: "Very dry mouth, no tears, or hard to wake",
            urgency: .now
        ),
        RedFlag(
            id: "fever",
            text: "Any fever under 12 weeks old – and don't give fever medicine before they're seen",
            urgency: .now
        ),
        RedFlag(
            id: "few-nappies",
            text: "Fewer than 6 wet diapers a day after the first week",
            urgency: .soon
        ),
        RedFlag(
            id: "birth-weight",
            text: "Not back to birth weight by about two weeks",
            urgency: .soon
        ),
        RedFlag(
            id: "still-hungry",
            text: "Seems hungry after most feeds – that earns a weight check",
            urgency: .soon
        ),
        RedFlag(
            id: "sleepy",
            text: "Sleepy and hard to rouse for feeds, especially if born early",
            urgency: .soon
        ),
    ]

    /// The one line to leave a parent with.
    ///
    /// Close to the AAP's own wording, because it's the reassurance that
    /// actually lands: the right amount is defined by the baby, not the rule.
    static let bottomLine = """
        As long as your baby is growing and gaining weight, is content most of \
        the time, and isn't spitting up excessively, they're taking the right \
        amount for them.
        """

    /// Wet diapers alone aren't proof, which is why this is stated plainly.
    static let diaperCaveat = """
        Diaper counts alone don't guarantee enough intake – a baby can keep \
        wetting while still falling behind on weight. If they seem very sleepy, \
        are hard to wake for feeds, or aren't back to birth weight by two \
        weeks, ask for a weight check even if the diapers look fine.
        """

    static let sourceIDs = [
        "aap-amount-schedule", "aap-responsive", "aap-enough-milk",
        "cdc-cues", "cdc-how-much-formula",
    ]
}
