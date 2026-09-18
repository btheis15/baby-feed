import Foundation
import Testing
@testable import BabyFeed

/// The join link is the one piece of sync a person actually touches: it's what
/// the QR code contains and what arrives in a text message. Everything here is
/// about it failing safely rather than half-working.
struct SyncLinkTests {
    private let server = URL(string: "https://babyfeed.example.org:4443")!

    @Test func roundTrips() throws {
        let url = try #require(SyncLink.url(code: "D8WAQK", server: server))
        let invitation = try #require(SyncLink.invitation(from: url))
        #expect(invitation.code == "D8WAQK")
        #expect(invitation.server == server)
    }

    @Test func normalizesTheCodeItCarries() throws {
        let url = try #require(SyncLink.url(code: "d8w aqk", server: server))
        #expect(url.absoluteString.contains("code=D8WAQK"))
    }

    @Test func ignoresLinksThatArentInvites() {
        #expect(SyncLink.invitation(from: URL(string: "babyfeed://log/formula")!) == nil)
        #expect(SyncLink.invitation(from: URL(string: "https://example.org/join?code=D8WAQK")!) == nil)
    }

    @Test func refusesACodeOfTheWrongLength() {
        let url = URL(string: "babyfeed://join?code=D8W&server=https://babyfeed.example.org")!
        #expect(SyncLink.invitation(from: url) == nil)
    }

    @Test func readsTheOlderPathStyleLinkForACodeOnly() {
        // babyfeed://join/CODE carries no server, so it can only be used by a
        // phone that already knows one — invitation() must not invent one.
        let url = URL(string: "babyfeed://join/D8WAQK")!
        #expect(SyncLink.invitation(from: url) == nil)
        #expect(SyncLink.code(from: url) == "D8WAQK")
    }

    @Test func addsHTTPSToATypedAddress() {
        #expect(SyncLink.normalizedServerURL("babyfeed.example.org")?.absoluteString
                == "https://babyfeed.example.org")
        #expect(SyncLink.normalizedServerURL(" babyfeed.example.org/ ")?.absoluteString
                == "https://babyfeed.example.org")
    }

    @Test func plainHTTPIsOnlyAllowedOnTheHomeNetwork() {
        // A device token over plain http across the internet would be readable
        // by anything in between; on the LAN it's a reasonable way to try it.
        #expect(SyncLink.normalizedServerURL("http://192.168.1.50:8791") != nil)
        #expect(SyncLink.normalizedServerURL("http://mini.local:8791") != nil)
        #expect(SyncLink.normalizedServerURL("http://babyfeed.example.org") == nil)
    }

    @Test func knowsWhichAddressesArePrivate() {
        #expect(SyncLink.isPrivateHost("10.0.0.4"))
        #expect(SyncLink.isPrivateHost("172.16.3.2"))
        #expect(SyncLink.isPrivateHost("192.168.1.1"))
        #expect(SyncLink.isPrivateHost("Mac-mini.local"))
        #expect(!SyncLink.isPrivateHost("172.32.0.1"))
        #expect(!SyncLink.isPrivateHost("8.8.8.8"))
    }

    @Test func rejectsRubbish() {
        #expect(SyncLink.normalizedServerURL("") == nil)
        #expect(SyncLink.normalizedServerURL("   ") == nil)
        #expect(SyncLink.normalizedServerURL("https://") == nil)
    }
}
