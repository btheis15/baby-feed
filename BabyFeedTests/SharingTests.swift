import Foundation
import SwiftData
import Testing
@testable import BabyFeed

/// Where the server address comes from. Never from the bundle in a test: the
/// tests run inside the app, which would hand them this Mac's real address.
struct ServerConfigTests {
    @Test func noHostMeansNoServer() {
        #expect(ServerConfig.defaultURL(from: [:]) == nil)
        #expect(ServerConfig.defaultURL(from: ["Scheme": "http", "Host": ""]) == nil)
        #expect(ServerConfig.defaultURL(from: ["Scheme": "http", "Host": "   "]) == nil)
    }

    @Test func anUnexpandedPlaceholderIsNotAnAddress() {
        #expect(ServerConfig.defaultURL(from: ["Scheme": "http", "Host": "$(BABYFEED_SERVER_HOST)"]) == nil)
    }

    @Test func plainHTTPToTheHomeNetworkIsFine() {
        let url = ServerConfig.defaultURL(from: ["Scheme": "http", "Host": "your-mac-mini.local:8791"])
        #expect(url?.absoluteString == "http://your-mac-mini.local:8791")
        #expect(ServerConfig.defaultURL(from: ["Scheme": "http", "Host": "192.168.1.20:8791"]) != nil)
    }

    /// A token must never cross the internet unencrypted.
    @Test func plainHTTPToAPublicHostIsRefused() {
        #expect(ServerConfig.defaultURL(from: ["Scheme": "http", "Host": "babyfeed.example.org"]) == nil)
    }

    @Test func httpsAnywhere() {
        #expect(ServerConfig.defaultURL(from: ["Scheme": "https", "Host": "babyfeed.example.org:9444"])?.absoluteString
                == "https://babyfeed.example.org:9444")
        // No scheme given: https.
        #expect(ServerConfig.defaultURL(from: ["Host": "babyfeed.example.org"])?.scheme == "https")
        #expect(ServerConfig.defaultURL(from: ["Scheme": "ftp", "Host": "babyfeed.example.org"]) == nil)
    }
}

/// What the app reads back from the server, including the shapes older and
/// newer servers send.
struct PairingDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try SyncClient.decoder.decode(type, from: Data(json.utf8))
    }

    /// Joining or restoring as the caregiver this phone already is sends back
    /// no token. That used to fail to decode, so restoring onto a paired
    /// phone always failed.
    @Test func aNullTokenMeansKeepTheOneYouHave() throws {
        let pairing = try decode(SyncClient.Pairing.self, """
        {"token":null,"user_id":"0F6A2D0B-1D8B-4B7E-9C7E-2B3A4C5D6E7F","display_name":"Annette",
         "baby":null,"members":[],"babies":[],"server_id":"01AAB375"}
        """)
        #expect(pairing.token == nil)
        #expect(pairing.displayName == "Annette")
        #expect(pairing.serverID == "01AAB375")
        #expect(pairing.merged == nil, "not a personal phrase")
    }

    /// Enrolment answers with just the new identity.
    @Test func anEnrolmentHasNoBabies() throws {
        let pairing = try decode(SyncClient.Pairing.self, """
        {"token":"abc","user_id":"0F6A2D0B-1D8B-4B7E-9C7E-2B3A4C5D6E7F","display_name":"","server_id":"01AAB375"}
        """)
        #expect(pairing.token == "abc")
        #expect(pairing.babies.isEmpty)
        #expect(pairing.baby == nil)
    }

    @Test func aPersonalPhraseSaysWhetherItMerged() throws {
        let pairing = try decode(SyncClient.Pairing.self, """
        {"token":null,"user_id":"0F6A2D0B-1D8B-4B7E-9C7E-2B3A4C5D6E7F","display_name":"Brian",
         "baby":null,"members":[],"babies":[],"server_id":"01AAB375","merged":true,"retired_key":false}
        """)
        #expect(pairing.wasPersonalPhrase)
        #expect(pairing.merged == true)
    }

    /// A server from before sharing without credentials: no api, no id, no
    /// features. It decodes, and it's recognised as too old.
    @Test func theOldHealthShapeStillDecodes() throws {
        let health = try decode(SyncClient.Health.self, #"{"ok":true,"service":"babyfeed-server","paired_devices":4}"#)
        #expect(health.api == nil)
        #expect(health.serverID == nil)
        #expect(health.features.isEmpty)
        #expect(!SyncPlan.isCompatible(health))
    }

    @Test func todaysHealthShape() throws {
        let health = try decode(SyncClient.Health.self, """
        {"ok":true,"service":"babyfeed-server","api":2,"server_id":"01AAB375",
         "features":["enroll","join_as_member","member_invites","account_keys"],
         "enroll":"lan","enroll_available":false,"server_time":"2026-09-28T12:00:00.000Z"}
        """)
        #expect(health.api == 2)
        #expect(health.enrollAvailable == false)
        #expect(SyncPlan.isCompatible(health))
    }

    @Test func aRejectionCarriesItsCode() throws {
        let result = try decode(SyncClient.PushResult.self, """
        {"applied":[],"rejected":[{"table":"feeds","id":"0F6A2D0B-1D8B-4B7E-9C7E-2B3A4C5D6E7F","reason":"not a member","code":"not_a_member"},
                                  {"table":"feeds","id":null,"reason":"bad row"}]}
        """)
        #expect(result.rejected.map(\.code) == ["not_a_member", nil])
    }
}

/// The decisions about connecting, which can't be watched happening on a
/// phone at 3 a.m. and so are pinned here.
struct SyncPlanTests {
    @Test func comingToTheFrontOnlyReconnectsAPhoneThatWantsIt() {
        // Never asked: no Local Network prompt out of nowhere.
        #expect(!SyncPlan.shouldConnect(for: .foreground, wantsSync: false, optedOut: false))
        #expect(SyncPlan.shouldConnect(for: .foreground, wantsSync: true, optedOut: false))
        // "Stop syncing this phone" means it.
        #expect(!SyncPlan.shouldConnect(for: .foreground, wantsSync: true, optedOut: true))
        // Anything the parent asked for goes ahead, and undoes the opt-out.
        for reason: SyncPlan.ConnectReason in [.addedBaby, .backUp, .share] {
            #expect(SyncPlan.shouldConnect(for: reason, wantsSync: false, optedOut: true))
        }
    }

    @Test func aDifferentServerIdMeansTheServerWasReset() {
        #expect(SyncPlan.identity(stored: "A", reported: "A") == .same)
        #expect(SyncPlan.identity(stored: "A", reported: "B") == .reset)
        #expect(SyncPlan.identity(stored: nil, reported: "B") == .firstSeen)
        // A server too old to say is taken as it is.
        #expect(SyncPlan.identity(stored: "A", reported: nil) == .same)
    }

    @Test func onlyAnUntouchedNamelessBabyIsAPlaceholder() {
        #expect(SyncPlan.isPlaceholder(name: "", birthDate: nil, isShared: false, rowCount: 0))
        #expect(SyncPlan.isPlaceholder(name: "  ", birthDate: nil, isShared: false, rowCount: 0))
        #expect(!SyncPlan.isPlaceholder(name: "Nora", birthDate: nil, isShared: false, rowCount: 0))
        #expect(!SyncPlan.isPlaceholder(name: "", birthDate: .now, isShared: false, rowCount: 0))
        #expect(!SyncPlan.isPlaceholder(name: "", birthDate: nil, isShared: true, rowCount: 0))
        #expect(!SyncPlan.isPlaceholder(name: "", birthDate: nil, isShared: false, rowCount: 1),
                "a feed logged before anyone typed a name is real")
    }

    @Test func notAMemberStopsThatBabyOnly() {
        let nora = UUID(), sam = UUID(), feed = UUID(), otherFeed = UUID()
        let rejected = [
            SyncClient.PushResult.Rejected(table: "feeds", id: feed, reason: "not a member", code: "not_a_member"),
            SyncClient.PushResult.Rejected(table: "babies", id: sam, reason: "not a member", code: "not_a_member"),
            SyncClient.PushResult.Rejected(table: "feeds", id: otherFeed, reason: "bad row", code: "malformed"),
        ]
        let rows: [UUID: UUID] = [feed: nora, otherFeed: sam]
        let dropped = SyncPlan.babiesNoLongerShared(rejected: rejected) { table, id in
            table == "babies" ? id : rows[id]
        }
        #expect(dropped == [nora, sam])
    }

    @Test func afterLosingItsTokenAPhoneTriesAgainAtMostHourly() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(SyncPlan.mayReconnect(lastAttempt: nil, now: now))
        #expect(!SyncPlan.mayReconnect(lastAttempt: now.addingTimeInterval(-600), now: now))
        #expect(SyncPlan.mayReconnect(lastAttempt: now.addingTimeInterval(-3600), now: now))
    }

    @Test func notBeingHomeIsItsOwnCalmError() {
        #expect(SyncError.classify(URLError(.cannotFindHost)) == .away)
        #expect(SyncError.classify(URLError(.timedOut)) == .away)
        #expect(SyncError.classify(URLError(.notConnectedToInternet)) == .away)
        #expect(SyncError.classify(URLError(.networkConnectionLost)) == .away)
        #expect(SyncError.classify(URLError(.badServerResponse)) != .away)
        #expect(SyncError.classify(SyncError.unpaired) == .unpaired)
    }

    @Test func awayTextCountsWhatsWaiting() {
        #expect(SyncPlan.awayText(pending: 0) == "Will sync when you're home")
        #expect(SyncPlan.awayText(pending: 1).hasSuffix("1 change waiting"))
        #expect(SyncPlan.awayText(pending: 4).hasSuffix("4 changes waiting"))
    }

    @Test func theCodeIsReadOutInTwoThrees() {
        #expect(ShareBabySheet.grouped("d8waqk") == "D8W AQK")
    }
}

/// Adding the baby from onboarding, and what joining replaces.
@MainActor
struct BabyStoreSharingTests {
    @Test func theFirstBabyFillsInThePlaceholder() throws {
        let container = try AppSchema.inMemoryContainer()
        let context = container.mainContext
        let placeholder = Baby(name: "", birthDate: nil)
        context.insert(placeholder)
        try context.save()

        let birthday = Date(timeIntervalSince1970: 1_790_000_000)
        let baby = BabyStore.createBaby(name: " Nora ", birthDate: birthday, sex: .female,
                                        birthWeightGrams: 3400, in: context)

        #expect(baby.uuid == placeholder.uuid, "filled in, not added beside it")
        #expect(BabyStore.allBabies(in: context).count == 1)
        #expect(baby.name == "Nora")
        #expect(baby.needsUpload)
        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
        #expect(weights.count == 1)
        #expect(weights.first?.grams == 3400)
        #expect(weights.first?.date == birthday, "the birth weight is dated the birthday")
        #expect(!BabyStore.isPlaceholder(baby, in: context))
    }

    @Test func realBabiesLeaveOutThePlaceholder() throws {
        let container = try AppSchema.inMemoryContainer()
        let context = container.mainContext
        let empty = Baby(name: "", birthDate: nil)
        let nora = Baby(name: "Nora", birthDate: nil)
        let unnamedButUsed = Baby(name: "", birthDate: nil)
        context.insert(empty)
        context.insert(nora)
        context.insert(unnamedButUsed)
        context.insert(DiaperEntry(babyID: unnamedButUsed.uuid, kind: .wet))
        try context.save()

        let real = Set(BabyStore.realBabies(in: context).map(\.uuid))
        #expect(real == [nora.uuid, unnamedButUsed.uuid])

        BabyStore.removePlaceholders(keeping: nil, in: context)
        #expect(BabyStore.allBabies(in: context).count == 2)
    }
}
