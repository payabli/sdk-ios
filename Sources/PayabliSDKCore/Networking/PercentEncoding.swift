import Foundation

/// Percent-encoding for the parts of a URL this SDK builds.
///
/// In Core rather than in a capability module because the card-present and card-not-present
/// surfaces both build a path from a value they were handed, and a capability never depends on a
/// sibling, so the alternative is one copy each. A URL encoder is the wrong thing to keep two of:
/// the copies drift on which characters they cover, and the one that falls behind sends a request
/// nobody wrote.
///
/// It sits beside `PayabliRequest`, where path construction already lives. The transport refuses an
/// authority, a scheme, a foreign origin and a path that escapes the base; this is the rest, the
/// characters that change a request without leaving it.
package enum PercentEncoding {
    /// Unreserved characters, per RFC 9110 Section 2.3's reference to RFC 3986 Section 2.3.
    /// Everything else in a segment is encoded.
    private static let unreserved: Set<UInt8> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8
    )

    /// Upper case, because RFC 3986 Section 6.2.2.1 says a producer writes the hexadecimal digits
    /// of a percent-encoding in upper case.
    private static let hex = Array("0123456789ABCDEF")

    /// Encodes `value` as a single path segment, every byte outside the unreserved set percent-encoded.
    /// A `?`, `#` or `/` in an identifier stays part of it instead of becoming a query, a fragment or another route.
    /// `urlPathAllowed` is not this: it admits the sub-delimiters and `:@`, which a route is free to give meaning to.
    ///
    /// - Parameter value: the segment text to encode; empty stays empty, a different route, not a refusal.
    /// - Returns: the percent-encoded segment, every other UTF-8 byte in upper-case hex.
    package static func segment(_ value: String) -> String {
        var encoded = ""
        encoded.reserveCapacity(value.utf8.count)
        for byte in value.utf8 {
            if unreserved.contains(byte) {
                // Every member of the unreserved set is ASCII, so the byte is its own scalar.
                encoded.unicodeScalars.append(UnicodeScalar(byte))
            } else {
                encoded.append("%")
                encoded.append(hex[Int(byte >> 4)])
                encoded.append(hex[Int(byte & 0x0F)])
            }
        }
        return encoded
    }

    /// Places an already-encoded segment into a route template's `{placeholder}`, so a request's path and the template
    /// its log names have one definition. A template without a placeholder traps: it is a route wired to the wrong
    /// helper, not a value a caller could correct.
    ///
    /// - Parameter template: the route with one `{placeholder}`, as `/api/v2/MoneyIn/void/{transId}`.
    /// - Parameter segment: the already-encoded value that takes the placeholder's place.
    /// - Returns: the resolved path.
    package static func path(from template: String, segment: String) -> String {
        guard let open = template.firstIndex(of: "{"),
              let close = template[open...].firstIndex(of: "}")
        else { preconditionFailure("a resolved route needs a {placeholder}: \(template)") }
        return String(template[..<open]) + segment + String(template[template.index(after: close)...])
    }
}
