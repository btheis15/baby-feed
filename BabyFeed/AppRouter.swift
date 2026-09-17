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
    var pendingJoinCode: String?
    var showJoinSheet = false

    func openLog(kind: FeedKind?) {
        tab = .today
        pendingLogKind = kind ?? .formula
        showLogSheet = true
    }

    func openJoin(code: String?) {
        pendingJoinCode = code
        showJoinSheet = true
    }

    /// babyfeed://log, babyfeed://log/formula, babyfeed://join/ABC123, babyfeed://home
    func handle(url: URL) {
        guard url.scheme == DeepLink.scheme else { return }
        switch url.host {
        case "log":
            let kind = url.pathComponents.dropFirst().first.flatMap(FeedKind.init(rawValue:))
            openLog(kind: kind)
        case "join":
            openJoin(code: url.pathComponents.dropFirst().first)
        default:
            tab = .today
        }
    }
}
