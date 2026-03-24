import Foundation

/// All Payabli backend API endpoints used by the SDK.
/// The 3 TapToPay endpoints are new (attestation flow).
/// The MoneyIn endpoints already exist and are used by the POC.
enum Endpoint {

    // MARK: - Attestation (new endpoints)

    /// Phase A: get a random nonce for attestKey(). iOS only.
    case challenge
    /// Phase A: register the attested key with the backend. iOS only.
    case attest
    /// Phase B: fetch Fiserv credentials. Requires assertion (iOS) or Play Integrity token (Android).
    case config(entry: String)

    // MARK: - Transaction orchestration (existing endpoints)

    /// Step 1 of charge: create transaction record in Payabli.
    case initiate
    /// Step 3 of charge: send Fiserv result back to Payabli.
    case update(paymentTransId: String)

    var path: String {
        switch self {
        case .challenge:
            return "/api/v2/device/taptopay/challenge"
        case .attest:
            return "/api/v2/device/taptopay/attest"
        case .config:
            return "/api/v2/TapToPay/config"
        case .initiate:
            return "/api/v2/MoneyIn/initiate"
        case .update(let id):
            return "/api/v2/MoneyIn/update/\(id)"
        }
    }

    var method: String {
        switch self {
        case .challenge, .attest, .initiate:
            return "POST"
        case .config:
            return "GET"
        case .update:
            return "PATCH"
        }
    }
}
