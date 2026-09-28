import Foundation

/// The sync server this build was made for, so nobody types an address.
///
/// It comes from `ServerConfig.plist` in the app bundle, which git ignores (the
/// repo is public; `Config/ServerConfig.example.plist` shows the shape). A
/// build without one has no default server: the app works entirely on the
/// phone, and Caregivers → Advanced still takes a typed address.
///
/// Kept apart from `SyncLink` on purpose. Tests run inside the app bundle, so
/// anything that read the bundle there would pick up this Mac's real address.
enum ServerConfig {
    static let resourceName = "ServerConfig"

    /// This build's server, read once: screens ask on every redraw.
    static let current: URL? = defaultURL()

    static func defaultURL(bundle: Bundle = .main) -> URL? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return defaultURL(from: values)
    }

    /// `Scheme` and `Host` ("http", "your-mac-mini.local:8791"). Nil when the
    /// host is missing or is still a build-setting placeholder, and for plain
    /// http to anything but a home-network address.
    static func defaultURL(from values: [String: Any]) -> URL? {
        let scheme = (values["Scheme"] as? String ?? "https").trimmingCharacters(in: .whitespaces).lowercased()
        let host = (values["Host"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !host.contains("$("), scheme == "http" || scheme == "https" else { return nil }
        return SyncLink.normalizedServerURL("\(scheme)://\(host)")
    }
}
