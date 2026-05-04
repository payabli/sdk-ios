import Foundation

// MARK: - /config wire types (PRD §8.2)
//
// Generic envelope scaffolding (`Status`, `DeclineEnvelope`, `Success<T>`,
// `declineOutcome(from:)`) lives in `PayabliSDKCore/Networking/ResponseEnvelope.swift`
// as `PayabliEnvelope.*`. Only the endpoint-specific payload lives here.

/// Payload carried inside `responseData` on success for
/// `GET /api/v2/device/taptopay/config/{entry}`.
///
/// The SDK flattens `credentials` into `TTPConfig.providerCredentials`
/// for the `TapToPayProvider` to consume (see PRD FR-11B.3, NFR-5D).
struct ConfigCredentialsPayload: Decodable {
    let credentials: [String: String]?
}
