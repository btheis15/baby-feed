import Foundation

/// The link that gets a second caregiver onto the log.
///
/// It carries both halves of what the other phone needs — which server, and
/// the code — because the server is a machine at your house with an address
/// nobody should have to type at 3 a.m.
///
///     babyfeed://join?code=D8WAQK&server=https%3A%2F%2Fbabyfeed.example.org%3A4443
///
/// Two ways to use one: send it (Messages, AirDrop — tapping it opens the app
/// straight onto the join screen), or show it as a QR code. The stock Camera
/// app reads a QR and offers to open the URL, so the other phone needs no
/// scanner inside Baby Feed, and Baby Feed needs no camera permission.
enum SyncLink {
    static let host = "join"

    struct Invitation: Equatable {
        var code: String
        var server: URL
    }

    static func url(code: String, server: URL) -> URL? {
        var components = URLComponents()
        components.scheme = DeepLink.scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "code", value: SyncMerge.normalizedInviteCode(code)),
            URLQueryItem(name: "server", value: server.absoluteString),
        ]
        return components.url
    }

    /// Reads a join link. Also accepts the older `babyfeed://join/CODE` shape,
    /// which has no server in it — the phone has to already know one, so it's
    /// only useful for a second baby on a phone that's already paired.
    static func invitation(from url: URL) -> Invitation? {
        guard url.scheme == DeepLink.scheme, url.host == host else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []

        let rawCode = items.first { $0.name == "code" }?.value
            ?? url.pathComponents.dropFirst().first
        guard let rawCode else { return nil }
        let code = SyncMerge.normalizedInviteCode(rawCode)
        guard SyncMerge.isPlausibleInviteCode(code) else { return nil }

        if let raw = items.first(where: { $0.name == "server" })?.value,
           let server = normalizedServerURL(raw) {
            return Invitation(code: code, server: server)
        }
        return nil
    }

    /// Just the code, for a link with no server on a phone that already has one.
    static func code(from url: URL) -> String? {
        guard url.scheme == DeepLink.scheme, url.host == host else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let raw = items.first { $0.name == "code" }?.value ?? url.pathComponents.dropFirst().first
        guard let raw else { return nil }
        let code = SyncMerge.normalizedInviteCode(raw)
        return SyncMerge.isPlausibleInviteCode(code) ? code : nil
    }

    /// Cleans up an address typed by hand: adds the scheme, drops a trailing
    /// slash, refuses anything that isn't a web address.
    ///
    /// Plain `http` is allowed only for a private address, so trying it on the
    /// home network works while a token can never be sent unencrypted across
    /// the internet.
    static func normalizedServerURL(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty else { return nil }
        if url.scheme == "http" && !isPrivateHost(host) { return nil }
        return url
    }

    /// Home-network addresses: 10.x, 192.168.x, 172.16–31.x, and .local names.
    static func isPrivateHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".local") { return true }
        let parts = lower.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 127 { return true }
        return false
    }
}
