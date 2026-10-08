import Foundation
import Testing
@testable import BabyFeed

struct LoggingInputTests {
    private let posix = Locale(identifier: "en_US_POSIX")

    @Test func exactMillilitersAreKeptRatherThanSnappedToTheStep() {
        #expect(VolumeUnit.milliliters.roundedToPrecision(75) == 75)
        #expect(VolumeUnit.milliliters.rounded(75) != 75)
        #expect(VolumeUnit.ounces.roundedToPrecision(2.34) == 2.25)
        #expect(VolumeUnit.ounces.roundedToPrecision(2.7) == 2.75)
    }

    @Test func switchingUnitConvertsTheSameAmount() {
        #expect(VolumeUnit.milliliters.converted(4, from: .ounces) == 118)
        #expect(abs(VolumeUnit.ounces.converted(118, from: .milliliters) - 4) < 0.0001)
    }

    @Test func theOtherUnitGoesInParentheses() {
        #expect(VolumeUnit.ounces.formatWithOther(milliliters: 118.29, locale: posix) == "4 oz (118 ml)")
        #expect(VolumeUnit.milliliters.formatWithOther(milliliters: 90, locale: posix) == "90 ml (3 oz)")
        let feed = FeedEntry(kind: .formula, amountML: 90)
        #expect(feed.detailText(unit: .milliliters) == VolumeUnit.milliliters.format(milliliters: 90))
        #expect(feed.detailText(unit: .milliliters, showsOther: true).contains("("))
    }

    @Test func ouncesShowToTheQuarter() {
        let oz = VolumeUnit.ounces
        #expect(oz.format(milliliters: oz.toMilliliters(2.25), locale: posix) == "2.25 oz")
        #expect(oz.format(milliliters: oz.toMilliliters(3.75), locale: posix) == "3.75 oz")
        // A converted amount rounds to the quarter, not to two stray decimals.
        #expect(oz.format(milliliters: 90, locale: posix) == "3 oz")
        #expect(VolumeUnit.ounceFractions.map(\.value) == [0.25, 0.5, 0.75])
    }

    @Test func typedAmountsParseWithEitherSeparator() {
        #expect(LogFeedSheet.parseAmount("75", locale: posix) == 75)
        #expect(LogFeedSheet.parseAmount("2.5", locale: posix) == 2.5)
        #expect(LogFeedSheet.parseAmount("2,5", locale: Locale(identifier: "de_DE")) == 2.5)
        #expect(LogFeedSheet.parseAmount("", locale: posix) == nil)
    }

    @Test func nursingWithoutBottlesNeverReadsAsZero() {
        let nursed = FeedSummary([FeedEntry(kind: .nursing, durationMinutes: 15),
                                  FeedEntry(kind: .nursing, durationMinutes: 20)])
        #expect(nursed.isNursingOnly)
        #expect(nursed.nursingText == "35 min")

        let noLength = FeedSummary([FeedEntry(kind: .nursing)])
        #expect(noLength.nursingText == "1 nursing")

        let bottle = FeedSummary([FeedEntry(kind: .formula, amountML: 90)])
        #expect(!bottle.isNursingOnly)
        #expect(bottle.nursingText == nil)
    }

    @MainActor
    @Test func theQuickLinkOpensTheQuickMenu() {
        let router = AppRouter()
        router.tab = .health
        router.handle(url: DeepLink.quickLog)
        #expect(router.tab == .today)
        #expect(router.sheet?.id == "quickLog")
    }

    @Test func theDiaperSheetsChipsReadLikeTheFeedSheets() {
        #expect(LogDiaperSheet.chipLabel(0) == "Now")
        #expect(LogDiaperSheet.chipLabel(15) == "15 min ago")
        #expect(LogDiaperSheet.chipLabel(60) == "1 hr ago")
    }
}
