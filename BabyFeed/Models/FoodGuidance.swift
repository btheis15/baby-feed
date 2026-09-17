import Foundation

/// What a baby can eat, and what to keep away from them, by age.
///
/// Every statement here traces to the AAP, CDC or WHO – see `Source`. This is
/// published guidance, not a diagnosis: ages are the consensus starting point
/// and the pediatrician always wins. Where bodies differ (the AAP says "not
/// before 4 months, around 6 months"; WHO says exclusive breastfeeding to 6
/// months) the more cautious reading is used.
enum FoodGuidance {
    // MARK: Sources

    struct Source: Identifiable, Hashable {
        let id: String
        let organisation: String
        let title: String
        let url: URL

        init(id: String, organisation: String, title: String, url: String) {
            self.id = id
            self.organisation = organisation
            self.title = title
            self.url = URL(string: url)!
        }
    }

    static let sources: [Source] = [
        Source(
            id: "aap-solids",
            organisation: "American Academy of Pediatrics",
            title: "When Can Babies Start Solid Foods? Readiness & Feeding Tips",
            url: "https://www.healthychildren.org/English/ages-stages/baby/feeding-nutrition/Pages/starting-solid-foods.aspx"
        ),
        Source(
            id: "aap-infant-feeding",
            organisation: "American Academy of Pediatrics",
            title: "Infant Food and Feeding",
            url: "https://www.aap.org/en/patient-care/healthy-active-living-for-families/infant-food-and-feeding/"
        ),
        Source(
            id: "aap-factsheet",
            organisation: "American Academy of Pediatrics",
            title: "Healthy Habits Start Early: Tips for Introducing Solid Foods (PDF)",
            url: "https://downloads.aap.org/AAP/PDF/AAP-Solid-Foods_Print-Fact-Sheet.pdf"
        ),
        Source(
            id: "aap-drinks",
            organisation: "American Academy of Pediatrics",
            title: "Recommended Drinks for Children Age 5 & Younger",
            url: "https://www.healthychildren.org/English/healthy-living/nutrition/Pages/recommended-drinks-for-young-children-ages-0-5.aspx"
        ),
        Source(
            id: "cdc-avoid",
            organisation: "CDC",
            title: "Foods and Drinks to Avoid or Limit",
            url: "https://www.cdc.gov/infant-toddler-nutrition/foods-and-drinks/foods-and-drinks-to-avoid-or-limit.html"
        ),
        Source(
            id: "cdc-introduce",
            organisation: "CDC",
            title: "When, What, and How to Introduce Solid Foods",
            url: "https://www.cdc.gov/infant-toddler-nutrition/foods-and-drinks/when-what-and-how-to-introduce-solid-foods.html"
        ),
        Source(
            id: "cdc-milk",
            organisation: "CDC",
            title: "Cow's Milk and Milk Alternatives",
            url: "https://www.cdc.gov/infant-toddler-nutrition/foods-and-drinks/cows-milk-and-milk-alternatives.html"
        ),
        Source(
            id: "cdc-6-24",
            organisation: "CDC",
            title: "Foods and Drinks for 6 to 24 Month Olds",
            url: "https://www.cdc.gov/infant-toddler-nutrition/foods-and-drinks/index.html"
        ),
        Source(
            id: "who-iycf",
            organisation: "World Health Organization",
            title: "Infant and young child feeding",
            url: "https://www.who.int/news-room/fact-sheets/detail/infant-and-young-child-feeding"
        ),
    ]

    static func source(_ id: String) -> Source? { sources.first { $0.id == id } }

    // MARK: Stages

    /// What's appropriate during a stretch of the first two years.
    struct Stage: Identifiable, Equatable {
        let id: String
        let title: String
        /// Inclusive lower bound in months.
        let fromMonths: Int
        /// Exclusive upper bound in months, nil for the last stage.
        let toMonths: Int?
        /// The headline in a few words.
        let summary: String
        /// What to offer during this stage.
        let canEat: [String]
        let sourceIDs: [String]

        func contains(months: Int) -> Bool {
            guard months >= fromMonths else { return false }
            guard let toMonths else { return true }
            return months < toMonths
        }

        var ageText: String {
            guard let toMonths else { return "\(fromMonths) months and up" }
            if fromMonths == 0 { return "Birth to \(toMonths) months" }
            return "\(fromMonths)–\(toMonths) months"
        }
    }

    static let stages: [Stage] = [
        Stage(
            id: "milk-only",
            title: "Milk only",
            fromMonths: 0,
            toMonths: 4,
            summary: "Breast milk or formula, and nothing else.",
            canEat: [
                "Breast milk or iron-fortified infant formula, on demand.",
                "No solid food. The AAP advises against starting solids before 4 months.",
                "No plain water – it displaces milk and can upset a young baby's sodium balance.",
                "Ask your pediatrician about vitamin D, which breastfed babies generally need.",
            ],
            sourceIDs: ["aap-solids", "who-iycf", "aap-drinks"]
        ),
        Stage(
            id: "watch-for-readiness",
            title: "Watching for readiness",
            fromMonths: 4,
            toMonths: 6,
            summary: "Still milk-led. Start looking for the signs below.",
            canEat: [
                "Breast milk or formula is still the whole diet.",
                "Solids are possible from 4 months if your baby is clearly ready, but around 6 months is the recommendation.",
                "If your baby has severe eczema or a known food allergy, talk to your pediatrician before starting – they may want to begin allergens earlier and supervised.",
            ],
            sourceIDs: ["aap-solids", "cdc-introduce"]
        ),
        Stage(
            id: "first-foods",
            title: "First foods",
            fromMonths: 6,
            toMonths: 9,
            summary: "Purées and well-mashed food alongside milk.",
            canEat: [
                "Iron-rich foods first: puréed meat, beans, lentils, or iron-fortified infant cereal.",
                "Single-ingredient purées and well-mashed vegetables and fruit, cooked soft, with no salt or sugar.",
                "One new food at a time, 3–5 days apart, so a reaction is easy to trace.",
                "Introduce common allergens – peanut, egg, dairy, wheat, soy, fish – rather than delaying them. Peanut as a thinned butter or peanut puff, never a glob.",
                "Water, about 4–8 oz a day in an open or straw cup.",
                "Prefer oat, barley or multigrain cereal over rice-only, which raises arsenic exposure.",
                "Breast milk or formula is still the main source of nutrition.",
            ],
            sourceIDs: ["cdc-introduce", "aap-solids", "aap-factsheet", "cdc-6-24"]
        ),
        Stage(
            id: "more-texture",
            title: "More texture",
            fromMonths: 9,
            toMonths: 12,
            summary: "Lumpier food and soft finger foods.",
            canEat: [
                "Soft finger foods cut small: well-cooked vegetables, soft fruit, shredded meat, pasta.",
                "Lumpier, thicker textures and combined foods rather than smooth purées.",
                "Two to three meals a day plus snacks, around milk feeds.",
                "Full-fat plain yogurt and cheese in small pieces – dairy foods are fine even though cow's milk as a drink is not.",
                "Practice with an open cup.",
            ],
            sourceIDs: ["cdc-6-24", "aap-factsheet"]
        ),
        Stage(
            id: "toddler",
            title: "Family food",
            fromMonths: 12,
            toMonths: nil,
            summary: "Whole cow's milk is now fine. Still no added sugar.",
            canEat: [
                "Whole pasteurized cow's milk, unflavoured – about 2 servings of dairy a day. It's a drink, not a meal, and too much crowds out iron-rich food.",
                "The same foods the family eats, chopped small and without added salt or sugar.",
                "Water and plain milk as the everyday drinks.",
                "100% juice is unnecessary; if offered at all, no more than 4 oz a day.",
                "Still no added sugars before 24 months, and still no caffeine.",
                "Breastfeeding can continue as long as you both want – WHO suggests to 2 years or beyond.",
            ],
            sourceIDs: ["cdc-milk", "aap-drinks", "cdc-avoid", "who-iycf"]
        ),
    ]

    /// The stage covering a given age in months.
    static func stage(forMonths months: Int) -> Stage {
        stages.first { $0.contains(months: max(0, months)) } ?? stages[stages.count - 1]
    }

    // MARK: Readiness

    /// AAP's signs that a baby is ready for solids. Readiness is developmental,
    /// not a birthday, which is why these sit next to the age bands.
    static let readinessSigns: [String] = [
        "Sits up alone, or with support",
        "Holds their head and neck steady",
        "Opens their mouth when food comes",
        "Swallows food instead of pushing it back out",
        "Brings objects to their mouth",
        "Tries to grasp small objects",
        "Moves food from the front of the tongue to the back to swallow",
    ]

    // MARK: Things to avoid

    /// Why something is off the menu.
    enum AvoidReason: String {
        case safety = "Safety"
        case choking = "Choking risk"
        case nutrition = "Nutrition"
    }

    struct AvoidRule: Identifiable, Equatable {
        let id: String
        let food: String
        /// Age in months from which this is no longer a concern. Nil means it
        /// applies at every age in the first two years.
        let clearedAtMonths: Int?
        /// What replaces the blanket rule once the age passes, if anything.
        let afterwards: String?
        let reason: AvoidReason
        let detail: String
        let sourceIDs: [String]

        /// Whether this still applies to a baby of the given age.
        func applies(atMonths months: Int) -> Bool {
            guard let clearedAtMonths else { return true }
            return months < clearedAtMonths
        }

        var ageText: String {
            guard let clearedAtMonths else { return "Any age" }
            return "Before \(clearedAtMonths) months"
        }
    }

    static let avoidRules: [AvoidRule] = [
        AvoidRule(
            id: "honey",
            food: "Honey",
            clearedAtMonths: 12,
            afterwards: "Fine from 12 months.",
            reason: .safety,
            detail: "Can cause infant botulism, a severe food poisoning. Don't add it to food, water, formula or a pacifier either.",
            sourceIDs: ["cdc-avoid"]
        ),
        AvoidRule(
            id: "cows-milk",
            food: "Cow's milk as a drink",
            clearedAtMonths: 12,
            afterwards: "Whole pasteurized milk from 12 months, about 2 servings of dairy a day.",
            reason: .nutrition,
            detail: "Risks intestinal bleeding, carries more protein and minerals than a baby's kidneys should handle, and lacks the nutrients they need. Yogurt and cheese as foods are fine earlier.",
            sourceIDs: ["cdc-milk", "cdc-avoid"]
        ),
        AvoidRule(
            id: "juice",
            food: "Juice",
            clearedAtMonths: 12,
            afterwards: "Unnecessary, but if offered, no more than 4 oz a day of 100% juice for ages 1–3.",
            reason: .nutrition,
            detail: "No juice at all before 12 months. Whole fruit is always better than juice. Avoid anything labelled juice drink or fruit-flavoured – that's added sugar.",
            sourceIDs: ["aap-drinks", "cdc-avoid"]
        ),
        AvoidRule(
            id: "water-early",
            food: "Plain water",
            clearedAtMonths: 6,
            afterwards: "About 4–8 oz a day from 6 months, in an open or straw cup.",
            reason: .safety,
            detail: "Before 6 months water displaces the milk a baby needs and can dilute their blood sodium.",
            sourceIDs: ["cdc-6-24", "aap-drinks"]
        ),
        AvoidRule(
            id: "added-sugar",
            food: "Added sugars",
            clearedAtMonths: 24,
            afterwards: "Still best kept low after 24 months.",
            reason: .nutrition,
            detail: "None before 24 months. Hides in flavoured yogurt, muffins, cookies and sweetened drinks, and crowds out food they actually need.",
            sourceIDs: ["cdc-avoid"]
        ),
        AvoidRule(
            id: "caffeine",
            food: "Caffeine",
            clearedAtMonths: 24,
            afterwards: nil,
            reason: .safety,
            detail: "No established safe amount for young children. Includes tea, coffee, soft drinks and sports drinks.",
            sourceIDs: ["cdc-avoid"]
        ),
        AvoidRule(
            id: "choking",
            food: "Choking hazards",
            clearedAtMonths: nil,
            afterwards: nil,
            reason: .choking,
            detail: "Whole grapes, nuts and seeds, popcorn, hot dogs and meat sticks, chunks of meat or cheese, raw vegetables, hard fruit chunks, globs of peanut butter, and hard, sticky or gooey sweets. Cut round foods lengthways and keep pieces small and soft.",
            sourceIDs: ["aap-solids", "aap-factsheet"]
        ),
        AvoidRule(
            id: "cereal-in-bottle",
            food: "Cereal in a bottle",
            clearedAtMonths: nil,
            afterwards: nil,
            reason: .choking,
            detail: "It won't help a baby sleep longer, and it adds a choking risk while making it easy to overfeed.",
            sourceIDs: ["aap-solids"]
        ),
        AvoidRule(
            id: "unpasteurized",
            food: "Unpasteurized food and drink",
            clearedAtMonths: nil,
            afterwards: nil,
            reason: .safety,
            detail: "Raw milk, juice, yogurt and soft cheeses can carry bacteria that cause severe illness in a baby.",
            sourceIDs: ["cdc-avoid"]
        ),
        AvoidRule(
            id: "high-mercury-fish",
            food: "High-mercury fish",
            clearedAtMonths: nil,
            afterwards: nil,
            reason: .safety,
            detail: "King mackerel, marlin, orange roughy, shark, swordfish, tilefish and bigeye tuna. Mercury harms the developing brain and nervous system. Lower-mercury fish is a good food.",
            sourceIDs: ["cdc-avoid"]
        ),
        AvoidRule(
            id: "salt",
            food: "Salty and heavily processed food",
            clearedAtMonths: nil,
            afterwards: nil,
            reason: .nutrition,
            detail: "Canned foods, processed meats, frozen dinners and packaged snacks. Cook without added salt.",
            sourceIDs: ["cdc-avoid"]
        ),
        AvoidRule(
            id: "plant-milks",
            food: "Plant-based milks",
            clearedAtMonths: nil,
            afterwards: nil,
            reason: .nutrition,
            detail: "Not a replacement for breast milk, formula or dairy milk. Fortified soy milk is the one nutritionally comparable option; the rest fall short.",
            sourceIDs: ["cdc-milk"]
        ),
        AvoidRule(
            id: "rice-only-cereal",
            food: "Rice-only infant cereal",
            clearedAtMonths: nil,
            afterwards: nil,
            reason: .safety,
            detail: "Not dangerous in itself, but making it the only cereal raises arsenic exposure. Rotate oat, barley and multigrain.",
            sourceIDs: ["aap-solids"]
        ),
    ]

    /// Rules that still apply at a given age, safety first.
    static func rules(applyingAtMonths months: Int) -> [AvoidRule] {
        avoidRules
            .filter { $0.applies(atMonths: max(0, months)) }
            .sorted { lhs, rhs in
                if lhs.reason != rhs.reason {
                    return order(lhs.reason) < order(rhs.reason)
                }
                return lhs.food < rhs.food
            }
    }

    /// Rules the baby has outgrown, newest milestone first – the "you can now
    /// do this" list, which is the reassuring half.
    static func rules(clearedByMonths months: Int) -> [AvoidRule] {
        avoidRules
            .filter { !$0.applies(atMonths: max(0, months)) }
            .sorted { ($0.clearedAtMonths ?? 0) > ($1.clearedAtMonths ?? 0) }
    }

    private static func order(_ reason: AvoidReason) -> Int {
        switch reason {
        case .safety: 0
        case .choking: 1
        case .nutrition: 2
        }
    }

    /// Whole months old, floor, from a day count.
    static func months(fromDays days: Int) -> Int {
        Int(Double(max(0, days)) / (365.25 / 12))
    }

    // MARK: Where the evidence is still moving

    /// A specific paper or position statement, named so it can be looked up.
    struct Citation: Identifiable, Hashable {
        var id: String { url.absoluteString }
        let authors: String
        let title: String
        /// "N Engl J Med. 2015;372(9):803-13."
        let publication: String
        let url: URL

        init(authors: String, title: String, publication: String, url: String) {
            self.authors = authors
            self.title = title
            self.publication = publication
            self.url = URL(string: url)!
        }
    }

    /// A question where informed, qualified people currently disagree, or where
    /// the research has moved and guidance hasn't fully caught up.
    ///
    /// Deliberately *not* a home for folk advice. Everything here is a
    /// peer-reviewed trial or a paediatric society's position paper, named and
    /// linked so it can be read and taken to a doctor. Claims that are simply
    /// known to be dangerous – raw milk for infants, homemade formula, honey
    /// for a cough under a year – are not "untested", they're tested and
    /// settled, and they live in the "Not yet" list instead.
    struct EmergingTopic: Identifiable, Equatable {
        let id: String
        let question: String
        /// What the AAP/CDC/WHO currently advise.
        let established: String
        /// What the newer or competing evidence indicates.
        let emerging: String
        /// The honest limitation – why this isn't settled.
        let limitation: String
        let citations: [Citation]

        static func == (lhs: EmergingTopic, rhs: EmergingTopic) -> Bool { lhs.id == rhs.id }
    }

    /// Shown under a disclaimer. Wording matters here, so it lives in one place.
    static let emergingDisclaimer = """
        These are real published studies and position papers, not folk advice – \
        but they are not the current US consensus, and nothing here is a \
        recommendation. Guidance changes because evidence like this accumulates, \
        and sometimes it doesn't hold up. Read them if you want the fuller \
        picture, and decide anything with your pediatrician rather than on the \
        strength of one trial.
        """

    static let emergingTopics: [EmergingTopic] = [
        EmergingTopic(
            id: "four-vs-six-months",
            question: "Four months or six, for starting solids?",
            established: "The AAP recommends around 6 months, and advises against starting before 4. WHO recommends exclusive breastfeeding for the first 6 months.",
            emerging: "ESPGHAN, the European paediatric gastroenterology society, concluded complementary foods should not be introduced before 17 weeks (about 4 months) and not delayed beyond 26 weeks (about 6 months), treating that whole window as acceptable rather than naming a single month.",
            limitation: "This is a genuine difference between professional bodies, not a fringe view – but it's a European guideline written for European infants, and it does not override your own pediatrician's advice.",
            citations: [
                Citation(
                    authors: "Fewtrell M, Bronsky J, Campoy C, et al. (ESPGHAN Committee on Nutrition)",
                    title: "Complementary Feeding: A Position Paper by ESPGHAN",
                    publication: "J Pediatr Gastroenterol Nutr. 2017;64(1):119–132.",
                    url: "https://onlinelibrary.wiley.com/doi/10.1097/MPG.0000000000001454"
                ),
            ]
        ),
        EmergingTopic(
            id: "early-allergen-introduction",
            question: "How early should allergens go in?",
            established: "Introduce common allergens rather than delaying them, from around 6 months, and speak to a doctor first if your baby has severe eczema or a known allergy. This itself is a reversal of the older advice to delay.",
            emerging: "The LEAP trial gave peanut to high-risk infants from 4–11 months and cut peanut allergy at age 5 from 13.7% to 1.9%. That evidence changed guidelines. The EAT trial then tried six allergens from 3 months in ordinary, exclusively breastfed infants: the headline result was null, but among families who actually managed the regimen, peanut and egg allergy fell sharply.",
            limitation: "LEAP was specifically high-risk infants, so it doesn't automatically generalise. EAT's positive result is per-protocol, and most families could not keep the regimen up – which is exactly why introducing six allergens at 3 months is not standard advice. Whole nuts remain a choking hazard at any age under 5; early introduction means thinned butter or puffs.",
            citations: [
                Citation(
                    authors: "Du Toit G, Roberts G, Sayre PH, et al. (LEAP Study Team)",
                    title: "Randomized Trial of Peanut Consumption in Infants at Risk for Peanut Allergy",
                    publication: "N Engl J Med. 2015;372(9):803–813.",
                    url: "https://www.nejm.org/doi/full/10.1056/NEJMoa1414850"
                ),
                Citation(
                    authors: "Perkin MR, Logan K, Tseng A, et al. (EAT Study Team)",
                    title: "Randomized Trial of Introduction of Allergenic Foods in Breast-Fed Infants",
                    publication: "N Engl J Med. 2016;374(18):1733–1743.",
                    url: "https://www.nejm.org/doi/full/10.1056/NEJMoa1514210"
                ),
            ]
        ),
        EmergingTopic(
            id: "baby-led-weaning",
            question: "Baby-led weaning instead of purées?",
            established: "The AAP doesn't endorse baby-led weaning over spoon-feeding, and the choking-hazard list applies either way. Iron-rich first foods are the priority.",
            emerging: "The BLISS randomised trial tested a version of baby-led weaning modified to protect iron intake and reduce choking risk. It found no more choking than spoon-feeding, and follow-up papers found no deficit in iron or zinc status.",
            limitation: "The striking finding cuts the other way too: 35% of infants choked at least once between 6 and 8 months regardless of method, and at 7 months over half had been offered a recognised choking-hazard food. The trial's lesson was less \"this method is safe\" than \"parents need to know which foods are hazards, supervise eating, and know choking first aid\".",
            citations: [
                Citation(
                    authors: "Fangupo LJ, Heath AM, Williams SM, et al.",
                    title: "A Baby-Led Approach to Eating Solids and Risk of Choking",
                    publication: "Pediatrics. 2016;138(4):e20160772.",
                    url: "https://publications.aap.org/pediatrics/article-abstract/138/4/e20160772/52372/A-Baby-Led-Approach-to-Eating-Solids-and-Risk-of"
                ),
                Citation(
                    authors: "Daniels L, Taylor RW, Williams SM, et al.",
                    title: "Impact of a modified version of baby-led weaning on iron intake and status: a randomised controlled trial",
                    publication: "BMJ Open. 2018;8(6):e019036.",
                    url: "https://bmjopen.bmj.com/content/8/6/e019036"
                ),
            ]
        ),
    ]
}
