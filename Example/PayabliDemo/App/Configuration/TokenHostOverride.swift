import Foundation

/// Reads the `-PayabliTokenHost` override into the token server's base URL.
///
/// Apart from `DemoConfiguration` because that type reads the gitignored
/// `Secrets`, which the demo's test target cannot compile.
enum TokenHostOverride {
    /// Accepts a bare host, `host:port`, or a full URL, so the override can be
    /// pasted from whatever the person has to hand.
    ///
    /// - Parameter raw: The override as given, already trimmed.
    /// - Parameter defaultPort: The port a bare host is reached on.
    /// - Returns: The base URL, or `nil` when `raw` names no host this app can reach.
    static func baseURL(from raw: String, defaultPort: Int) -> URL? {
        if raw.contains("://") {
            guard let parsed = URL(string: raw),
                  ["http", "https"].contains(parsed.scheme?.lowercased()),
                  parsed.host?.isEmpty == false
            else { return nil }
            return parsed
        }
        if let colon = raw.lastIndex(of: ":") {
            guard let port = Int(raw[raw.index(after: colon)...]), validPorts.contains(port) else { return nil }
            return url(host: String(raw[raw.startIndex ..< colon]), port: port)
        }
        return url(host: raw, port: defaultPort)
    }

    /// `URLComponents` traps on a negative port rather than failing.
    private static let validPorts = 1 ... 65535

    private static func url(host: String, port: Int) -> URL? {
        guard !host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        return components.url
    }
}
