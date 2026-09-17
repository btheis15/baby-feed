import Foundation
import Testing
@testable import BabyFeed

struct VolumeUnitTests {
    private let us = Locale(identifier: "en_US")

    @Test func ouncesRoundTripThroughMilliliters() {
        let ml = VolumeUnit.ounces.toMilliliters(2.5)
        #expect(abs(ml - 73.93375) < 0.001)
        #expect(abs(VolumeUnit.ounces.fromMilliliters(ml) - 2.5) < 0.0001)
    }

    @Test func millilitersAreIdentity() {
        #expect(VolumeUnit.milliliters.toMilliliters(90) == 90)
        #expect(VolumeUnit.milliliters.fromMilliliters(90) == 90)
    }

    @Test func formatsOuncesWithoutTrailingZero() {
        let oz = VolumeUnit.ounces
        #expect(oz.format(milliliters: oz.toMilliliters(3), locale: us) == "3 oz")
        #expect(oz.format(milliliters: oz.toMilliliters(2.5), locale: us) == "2.5 oz")
    }

    @Test func formatsMillilitersAsWholeNumbers() {
        #expect(VolumeUnit.milliliters.format(milliliters: 74.2, locale: us) == "74 ml")
        #expect(VolumeUnit.milliliters.format(milliliters: 120, locale: us) == "120 ml")
    }

    @Test func roundingSnapsToStep() {
        #expect(VolumeUnit.ounces.rounded(2.4999) == 2.5)
        #expect(VolumeUnit.ounces.rounded(2.2) == 2.0)
        #expect(VolumeUnit.milliliters.rounded(74) == 70)
        #expect(VolumeUnit.milliliters.rounded(76) == 80)
    }
}
