import Foundation

/// Reads the `Retry-After` field a response carries.
///
/// RFC 9110 Section 10.2.3 defines two forms and a recipient has to accept both: a delay in seconds, and
/// an HTTP-date. Section 5.6.7 requires the three date formats below, of which only the first is produced
/// by anything current.
enum RetryAfterHeader {
    static let name = "Retry-After"

    /// Formats in the order Section 5.6.7 lists them: IMF-fixdate, then the two obsolete forms.
    ///
    /// The zone is the literal `GMT` in the two that carry one, because the grammar admits nothing else:
    /// `GMT = %s"GMT"`, and both `IMF-fixdate` and `rfc850-date` end in it. A pattern reading the zone
    /// would accept any abbreviation or offset and take the sender at its word, which moves the instant
    /// by that zone's distance from GMT: `Tue, 14 Nov 2023 22:14:20 PST` reads as a wait of just over
    /// eight hours. That is above any sane ceiling, and a wait above the ceiling ends the retry, so a
    /// header that is not an HTTP-date would stop a request the computed backoff repeats in about a
    /// second.
    ///
    /// The locale is fixed because the month and day names are part of the format, and a device set to a
    /// locale that spells them differently would otherwise fail to parse a correct header. The time zone
    /// is fixed because the third form carries none.
    private static let dateFormats = [
        "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
        "EEEE, dd-MMM-yy HH:mm:ss 'GMT'",
        "EEE MMM d HH:mm:ss yyyy"
    ]

    /// The wait `response` asked for, or `nil` when it named none, named one that cannot be read, or named
    /// a negative delay.
    ///
    /// A value too large to hold saturates rather than wrapping, so it stays above any ceiling a caller
    /// compares it against instead of coming back as a short wait. A date already in the past reads as no
    /// wait rather than as a negative one.
    static func value(from response: PayabliResponse, now: Date = Date()) -> TimeInterval? {
        guard let raw = response.header(name)?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }

        // `delay-seconds` is one or more DIGIT and nothing else (RFC 9110 Section 10.2.3). The grammar is
        // checked before converting because `Int64` is looser than it: `+3600` and `-0` both convert, and
        // a malformed value read as a valid hint is worse than one read as absent. Above the ceiling it
        // ends the retry, so the wrong reading stops a request the computed backoff would have repeated.
        if !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }) {
            // A run too long to hold is still an instruction to wait, and an extreme one. Saturating keeps
            // it above any ceiling it is compared against; reporting no hint would fall back to the
            // computed backoff and retry in about a second.
            return Int64(raw).map(TimeInterval.init) ?? .greatestFiniteMagnitude
        }

        for format in dateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = format
            if let parsed = formatter.date(from: raw) {
                return max(0, parsed.timeIntervalSince(now))
            }
        }

        return nil
    }
}
