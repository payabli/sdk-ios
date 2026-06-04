import Foundation

enum PayabliPayInPaymentFlowSensitiveDataRedactor {
    static func redact(_ value: String) -> String {
        redactPANCandidates(in: value)
    }

    private static func redactPANCandidates(in value: String) -> String {
        let pattern = #"(?:\d[ -]?){13,19}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }

        var redacted = value
        let fullRange = NSRange(redacted.startIndex ..< redacted.endIndex, in: redacted)
        let matches = regex.matches(in: redacted, range: fullRange)

        for match in matches.reversed() {
            guard let range = Range(match.range, in: redacted) else { continue }
            let candidate = String(redacted[range])
            let digitCount = candidate.filter { $0.wholeNumberValue != nil }.count
            guard (13 ... 19).contains(digitCount) else { continue }
            redacted.replaceSubrange(range, with: "[REDACTED]")
        }

        return redacted
    }
}
