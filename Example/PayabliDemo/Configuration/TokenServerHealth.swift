import Foundation

/// What `GET /health` says about the environment the local token server serves.
///
/// A server pointed at another environment mints a token the app's host refuses,
/// and the refusal arrives as `401 "The signature key was not found"` — which
/// reads as a bad credential rather than a server pointed elsewhere. Comparing
/// the two here turns that into a sentence before any request is made.
///
/// Takes hosts and identifiers rather than a `PayabliEnvironment`, so the type
/// carries no SDK dependency and the demo's own test target can exercise it.
struct TokenServerHealth {
    let upstreamHost: String?
    let entry: String?

    init(body: Data) {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        upstreamHost = (json?["upstream"] as? String).flatMap { URL(string: $0)?.host }
        entry = (json?["entry"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One line for the Configuration screen.
    ///
    /// A server that reports neither value is an older build, which is no
    /// information rather than a mismatch. Both halves are compared, because a
    /// server can be on the right host with the wrong paypoint.
    func report(appHost: String?, appEntryPoint: String) -> String {
        var problems: [String] = []
        if let upstreamHost, let appHost, upstreamHost != appHost {
            problems.append("serving \(upstreamHost), app is on \(appHost)")
        }
        if let entry, !entry.isEmpty, !appEntryPoint.isEmpty, entry != appEntryPoint {
            problems.append("entry \(entry), app uses \(appEntryPoint)")
        }
        guard problems.isEmpty else {
            return "✗ Local token server is on another environment · "
                + problems.joined(separator: " · ")
        }
        if let upstreamHost {
            return "✓ Local token server healthy · \(upstreamHost)"
        }
        return "✓ Local token server healthy · environment not reported"
    }
}
