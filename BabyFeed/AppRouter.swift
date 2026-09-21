import Foundation
import Observation

/// Navigation state that outside events (widget taps, notification actions,
/// Siri) need to reach: which tab is showing and whether to open the log sheet.
@Observable
@MainActor
final class AppRouter {
    enum Tab: Hashable {
        case today, history, baby, settings
    }

    var tab: Tab = .today

    /// Which sheet is up — one value rather than a flag each, because only one
    /// sheet can be presented at a time. An invite arriving while the log sheet
    /// was open used to be swallowed silently, and the tap that carried it came
    /// from outside the app, so it should win.
    enum Sheet: Identifiable {
        case log(FeedKind)
        /// From a QR code or a sent link. Opens over whatever is on screen,
        /// because the person didn't come here through the app and shouldn't be
        /// left on a tab to go hunting from.
        case pairing(SyncLink.Invitation?)

        var id: String {
            switch self {
            case .log: "log"
            case .pairing: "pairing"
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
        let invitation: SyncLink.Invitation?
        if let complete = SyncLink.invitation(from: url) {
            invitation = complete
        } else if let code = SyncLink.code(from: url), let server = SyncCredentials.serverURL {
            // A link with no server in it: only usable because this phone is
            // already paired with one.
            invitation = SyncLink.Invitation(code: code, server: server)
        } else {
            // Nothing usable in the link — send them to the setup screen rather
            // than doing nothing visible.
            invitation = nil
        }
        sheet = .pairing(invitation)
    }
}
