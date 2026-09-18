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
    var pendingLogKind: FeedKind?
    var showLogSheet = false

    /// An invite this phone was handed, from a QR code or a sent link. Setting
    /// it opens the pairing sheet over whatever is on screen, because the tap
    /// that got here came from outside the app and shouldn't land the person on
    /// a tab to go hunting from.
    var pendingInvitation: SyncLink.Invitation?
    var showPairingSheet = false

    func openLog(kind: FeedKind?) {
        tab = .today
        pendingLogKind = kind ?? .formula
        showLogSheet = true
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
        if let invitation = SyncLink.invitation(from: url) {
            pendingInvitation = invitation
        } else if let code = SyncLink.code(from: url), let server = SyncCredentials.serverURL {
            // A link with no server in it: only usable because this phone is
            // already paired with one.
            pendingInvitation = SyncLink.Invitation(code: code, server: server)
        } else {
            // Nothing usable in the link — send them to the setup screen rather
            // than doing nothing visible.
            pendingInvitation = nil
        }
        showPairingSheet = true
    }
}
