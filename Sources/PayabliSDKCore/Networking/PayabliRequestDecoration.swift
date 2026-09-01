import Foundation

/// One step applied to every outbound request before it is sent.
///
/// A step receives a request and returns one. It cannot see the response or stop the send.
///
/// A step may await: the bearer's token read does.
protocol PayabliRequestDecoration: Sendable {
    func decorate(_ request: PayabliRequest) async throws -> PayabliRequest
}

extension [any PayabliRequestDecoration] {
    /// Left to right: index 0 runs first, and a later step sees an earlier one's output.
    func applyTo(_ request: PayabliRequest) async throws -> PayabliRequest {
        var decorated = request
        for decoration in self {
            decorated = try await decoration.decorate(decorated)
        }
        return decorated
    }
}

extension PayabliRequest {
    /// Merges `extra` over the request's own headers, with `extra` winning.
    ///
    /// A key differing only in case is removed. Header field names are case-insensitive (RFC 9110
    /// Section 5.1) and `URLRequest.setValue` replaces case-insensitively, so a duplicate left in the
    /// map leaves dictionary iteration order deciding which value reaches the wire.
    func withHeaders(_ extra: [String: String]) -> PayabliRequest {
        var merged = headers
        let incoming = Set(extra.keys.map { $0.lowercased() })
        for existing in merged.keys.filter({ incoming.contains($0.lowercased()) }) {
            merged.removeValue(forKey: existing)
        }
        merged.merge(extra) { _, new in new }
        return copyWith(headers: merged, body: body)
    }

    func withBody(_ newBody: Data?) -> PayabliRequest {
        copyWith(headers: headers, body: newBody)
    }

    /// Header field names are case-insensitive, so `content-type` counts as naming `Content-Type`.
    func namesHeader(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return headers.keys.contains { $0.lowercased() == lowered }
    }

    /// The one place a decorated request is rebuilt, so a property added to this type reaches every
    /// decoration.
    private func copyWith(headers: [String: String], body: Data?) -> PayabliRequest {
        PayabliRequest(
            method: method,
            path: path,
            query: query,
            headers: headers,
            body: body
        )
    }
}
