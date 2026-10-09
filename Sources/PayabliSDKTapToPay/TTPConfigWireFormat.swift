import Foundation

// MARK: - /config wire types

//
// Generic envelope scaffolding (`Status`, `DeclineEnvelope`, `Success<T>`,
// `declineOutcome(from:)`) lives in `PayabliSDKCore/Networking/ResponseEnvelope.swift`
// as `PayabliEnvelope.*`. Only the endpoint-specific payload lives here.

/// Payload carried inside `responseData` on success for `GET /api/v2/device/taptopay/config/{entry}`.
/// The SDK flattens `credentials` into `TTPConfig.providerCredentials` for the `TapToPayProvider`.
struct ConfigCredentialsPayload: Decodable {
    let credentials: [String: String]?
}
