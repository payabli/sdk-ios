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
    private static let dateFormats: [(pattern: String, twoDigitYear: Bool)] = [
        ("EEE, dd MMM yyyy HH:mm:ss 'GMT'", false),
        ("EEEE, dd-MMM-yy HH:mm:ss 'GMT'", true),
        ("EEE MMM d HH:mm:ss yyyy", false)
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
            formatter.dateFormat = format.pattern
            if let parsed = formatter.date(from: raw) {
                let instant = format.twoDigitYear ? century(of: parsed, near: now) : parsed
                return max(0, instant.timeIntervalSince(now))
            }
        }

        return nil
    }

    /// The instant a two-digit year names, by the rule rather than by the formatter's window.
    ///
    /// RFC 9110 Section 5.6.7 requires a recipient to read a timestamp "that appears to be more than 50
    /// years in the future as representing the most recent year in the past that had the same last two
    /// digits". `DateFormatter` answers from a window fixed at 1950 instead, which is not that rule and
    /// does not move: read in 2026, `09-Sep-50` is 1950.
    ///
    /// Getting it wrong here is the one reading that makes a client louder rather than quieter. A date in
    /// the past is no wait at all, so a long wait the server asked for becomes an immediate repeat,
    /// against a service that has just said it is under too much load.
    private static func century(of parsed: Date, near now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT") ?? calendar.timeZone
        guard let ceiling = calendar.date(byAdding: .year, value: 50, to: now) else { return parsed }

        // A century keeps the last two digits, so each step names the same header. The most recent year at
        // or below the ceiling is the one the rule asks for, and exactly 50 years ahead stays, since it is
        // "more than 50" that rolls back.
        //
        // Bounded rather than run to exhaustion: two steps already cover the formatter's whole window, and
        // a date arithmetic that stopped advancing would otherwise spin here.
        var instant = parsed
        for _ in 0 ..< 3 {
            guard let next = calendar.date(byAdding: .year, value: 100, to: instant), next <= ceiling
            else {
                break
            }
            instant = next
        }
        return instant
    }
}
