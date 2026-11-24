import Foundation

/// The card-not-present routes as templates. A log names a request by its template; `captureAuthorized`, `void`
/// and `read` embed a transaction identifier, so their resolved paths are sent and never logged.
enum PayInRoutes {
    static let storeMethod = "/api/TokenStorage/add"
    static let capture = "/api/v2/MoneyIn/getpaid"
    static let authorize = "/api/v2/MoneyIn/authorize"
    static let captureAuthorized = "/api/v2/MoneyIn/capture/{transId}"
    static let void = "/api/v2/MoneyIn/void/{transId}"
    static let read = "/api/MoneyIn/details/{transId}"
}
