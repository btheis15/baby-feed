import Foundation
import SwiftData
import Observation

/// Navigation state that outside events (widget taps, notification actions,
/// Siri) need to reach: which tab is showing and whether to open the log sheet.
@Observable
@MainActor
final class AppRouter {
    enum Tab: Hashable {
        case today, timeline, health, baby, settings
    }

    var tab: Tab = .today

    /// What the Timeline is showing. Set from outside it — "All diapers" on
    /// Today — as well as by its own chips.
    var timelineFilter: TimelineFilter = .all

    /// Whether the Timeline is on its charts rather than its list.
    var timelineShowsCharts = false

    func openTimeline(filter: TimelineFilter = .all) {
        timelineFilter = filter
        timelineShowsCharts = false
        tab = .timeline
    }

    /// Which sheet is up — one value rather than a flag each, because only one
    /// sheet can be presented at a time. An invite arriving while the log sheet
    /// was open used to be swallowed silently, and the tap that carried it came
    /// from outside the app, so it should win.
    enum Sheet: Identifiable {
        case log(FeedKind)
        /// A scanned QR or a sent link: joins straight away. Opens over
        /// whatever is on screen, because the person didn't come here through
        /// the app and shouldn't be left on a tab to go hunting from.
        case join(SyncLink.Invitation)
        /// Typing an address, a code or a phrase by hand (Caregivers →
        /// Advanced), or a link that didn't say which server.
        case pairing(code: String?)
        /// First launch: add your baby, join a log, or restore.
        case onboarding
        /// The QR for the current baby.
        case share(UUID)
        /// "Your recovery phrase", shown once right after backing up.
        case recoverySetup
        /// Editing one entry — from a timeline row, or the Edit on a toast.
        case editEntry(EntryRef)
        /// "+ Log something else": everything that isn't a feed or a diaper.
        case addEntry
        /// A new entry of one of those kinds, picked from `addEntry`.
        case newEntry(AddEntryKind)
        /// A note that's an update on a concern ("less red today").
        case newUpdate(PersistentIdentifier)
        /// A dose, of a medicine if one's chosen.
        case giveDose(PersistentIdentifier?)
        /// Setting up a medicine; the vitamin D offer fills it in.
        case newMedication(vitaminD: Bool)
        /// Starting a concern from a note that turned out to be one.
        case trackConcern(PersistentIdentifier)

        var id: String {
            switch self {
            case .log: "log"
            case .join: "join"
            case .pairing: "pairing"
            case .onboarding: "onboarding"
            case .share: "share"
            case .recoverySetup: "recoverySetup"
            case .editEntry(let ref): "edit-\(ref.id)"
            case .addEntry: "addEntry"
            case .newEntry(let kind): "new-\(kind.rawValue)"
            case .newUpdate(let id): "update-\(id.hashValue)"
            case .giveDose(let id): "dose-\(id?.hashValue ?? 0)"
            case .newMedication(let vitaminD): "medication-\(vitaminD)"
            case .trackConcern(let id): "track-\(id.hashValue)"
            }
        }
    }

    var sheet: Sheet?

    func openLog(kind: FeedKind?) {
        tab = .today
        sheet = .log(kind ?? .formula)
    }

    /// babyfeed://log, babyfeed://log/formula, babyfeed://home,
    /// babyfeed://join?code=ABC123&server=https://…
    func handle(url: URL) {
        guard url.scheme == DeepLink.scheme else { return }
        switch url.host {
        case "log":
            let kind = url.pathComponents.dropFirst().first.flatMap(FeedKind.init(rawValue:))
            openLog(kind: kind)
        case SyncLink.host:
            openJoin(url: url)
        default:
            tab = .today
        }
    }

    private func openJoin(url: URL) {
        if let complete = SyncLink.invitation(from: url) {
            sheet = .join(complete)
        } else if let code = SyncLink.code(from: url),
                  let server = SyncCredentials.serverURL ?? ServerConfig.current {
            // A link with no server in it (an older one): usable because this
            // phone, or this build, already knows one.
            sheet = .join(SyncLink.Invitation(code: code, server: server))
        } else {
            // Nothing usable in the link: the typed setup screen rather than
            // nothing visible.
            sheet = .pairing(code: SyncLink.code(from: url))
        }
    }
}
