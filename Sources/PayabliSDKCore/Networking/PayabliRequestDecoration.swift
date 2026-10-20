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
    ///
    /// - Parameter request: the request the first decoration receives.
    /// - Returns: the request after every decoration, the last one's output.
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
    /// A key differing only in case is removed first: header names are case-insensitive, and a
    /// duplicate left in the map leaves iteration order deciding which value reaches the wire.
    ///
    /// - Parameter extra: the headers to merge over the request's own, winning on a case-insensitive clash.
    /// - Returns: the request rebuilt with the merged headers.
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
    ///
    /// - Parameter name: the field name to look for, matched whatever its case.
    /// - Returns: whether the request carries a header of that name.
    func namesHeader(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return headers.keys.contains { $0.lowercased() == lowered }
    }

    /// The one place a decorated request is rebuilt, so a property added to this type reaches every
    /// decoration.
    ///
    /// - Parameter headers: the headers the rebuilt request carries.
    /// - Parameter body: the body the rebuilt request carries.
    /// - Returns: the rebuilt request, with the given headers and body in place of its own.
    private func copyWith(headers: [String: String], body: Data?) -> PayabliRequest {
        PayabliRequest(
            method: method,
            path: path,
            query: query,
            headers: headers,
            body: body,
            isCallerRefusal: isCallerRefusal
        )
    }
}
