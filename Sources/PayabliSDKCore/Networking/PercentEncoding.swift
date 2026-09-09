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

    /// Encodes `value` for use as a single path segment.
    ///
    /// Keeps the unreserved set and encodes every other byte of the UTF-8 encoding, so a `?`, `#`
    /// or `/` in an identifier stays part of the identifier instead of becoming a query, a fragment
    /// or another route.
    ///
    /// `addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)` is not this: that set admits
    /// the sub-delimiters `!$&'()*+,;=` and also `:@`, which a route is free to give meaning to.
    ///
    /// Whether a value is acceptable at all is the caller's question rather than this one's. An
    /// empty `value` encodes to an empty string, which is a different route rather than a refusal,
    /// so a caller that cannot accept that checks first.
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
}
