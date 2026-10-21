import Foundation

/// The raw result of a `PayabliService` call.
///
/// Carries no interpretation: `mapPayabliHTTPError` maps a non-2xx status to a typed error, and the
/// caller decides when to apply it.
package struct PayabliResponse: Sendable {
    package let statusCode: Int
    package let headers: [String: String]
    package let body: Data

    package init(
        statusCode: Int,
        headers: [String: String],
        body: Data
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    /// True for 2xx.
    package var isSuccessful: Bool {
        (200 ..< 300).contains(statusCode)
    }

    /// The value of `name`, matched without regard to case.
    /// Nothing normalizes the case reported here and HTTP/2 lower-cases every field name, so
    /// subscripting `headers` finds a field only when the sender spelled it the same way.
    ///
    /// - Parameter name: the field name to read, matched whatever its case.
    /// - Returns: the value carried under that field name, or `nil` when the response names none.
    package func header(_ name: String) -> String? {
        let lowered = name.lowercased()
        return headers.first { $0.key.lowercased() == lowered }?.value
    }
}

extension PayabliResponse: CustomStringConvertible {
    /// Never includes the headers or the body. A synthesized description prints every property, and this
    /// type reaches assertion failures and crash reports without passing the logger; a response body may
    /// carry cardholder data and a header may carry a credential.
    package var description: String {
        "PayabliResponse(status: \(statusCode), bodyBytes: \(body.count))"
    }
}
