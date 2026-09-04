import Foundation

/// The raw result of a `PayabliService` call.
///
/// Carries no interpretation: `mapPayabliHTTPError` maps a non-2xx status to a typed error, and the
/// caller decides when to apply it.
public struct PayabliResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(
        statusCode: Int,
        headers: [String: String],
        body: Data
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    /// True for 2xx.
    public var isSuccessful: Bool {
        (200 ..< 300).contains(statusCode)
    }

    /// The value of `name`, matched without regard to case.
    ///
    /// Header field names are case-insensitive (RFC 9110 Section 5.1) and nothing normalizes the case
    /// reported here, so subscripting `headers` finds a field only when the sender happened to spell it
    /// the same way. HTTP/2 lower-cases every field name. Read a header through this and not through the
    /// dictionary.
    public func header(_ name: String) -> String? {
        let lowered = name.lowercased()
        return headers.first { $0.key.lowercased() == lowered }?.value
    }

    /// The body decoded as UTF-8, or an empty string if it is not valid UTF-8.
    public func bodyAsText() -> String {
        String(data: body, encoding: .utf8) ?? ""
    }
}

extension PayabliResponse: CustomStringConvertible {
    /// Never includes the headers or the body. A synthesized description prints every property, and this
    /// type reaches assertion failures and crash reports without passing the logger; a response body may
    /// carry cardholder data and a header may carry a credential.
    public var description: String {
        "PayabliResponse(status: \(statusCode), bodyBytes: \(body.count))"
    }
}
