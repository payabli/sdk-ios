import XCTest
@testable import PayabliSDKTapToPay

/// Contract tests for the backend `PATCH /MoneyIn/update/{id}` wire format.
/// The backend still expects the top-level key `fiservResponse`; the SDK's
/// Swift field is named `providerResponse` and maps to that wire key via
/// `UpdateSuccessBody.CodingKeys`. These tests fail loudly if someone
/// removes or changes the mapping without a coordinated backend rollout.
final class TTPTransactionWireFormatTests: XCTestCase {

    func test_updateSuccessBody_serializesOpaqueJSONUnderFiservResponseKey() throws {
        let innerJSON = Data(#"{"transactionId":"abc","status":"approved"}"#.utf8)
        let payload = ProviderResponsePayload.opaqueJSON(innerJSON)
        let body = UpdateSuccessBody(providerResponse: payload)

        let wire = try JSONEncoder().encode(body)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: wire) as? [String: Any]
        )

        // The wire key must remain `fiservResponse`, not `providerResponse`.
        XCTAssertNotNil(parsed["fiservResponse"], "wire JSON lost the fiservResponse key")
        XCTAssertNil(parsed["providerResponse"], "Swift field name leaked into wire JSON")

        let inner = try XCTUnwrap(parsed["fiservResponse"] as? [String: Any])
        XCTAssertEqual(inner["transactionId"] as? String, "abc")
        XCTAssertEqual(inner["status"] as? String, "approved")
    }

    func test_updateSuccessBody_serializesPayloadOnlyUnderFiservResponseKey() throws {
        let payloadOnly = PayloadOnlyProviderResponse(
            provider: "test",
            encryptedPayload: "ZW5jcnlwdGVkLWJsb2I=",
            cardNetwork: "Visa",
            providerMetadata: ["traceId": "t-1"]
        )
        let body = UpdateSuccessBody(providerResponse: .payloadOnly(payloadOnly))

        let wire = try JSONEncoder().encode(body)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: wire) as? [String: Any]
        )

        let inner = try XCTUnwrap(parsed["fiservResponse"] as? [String: Any])
        XCTAssertEqual(inner["provider"] as? String, "test")
        XCTAssertEqual(inner["cardNetwork"] as? String, "Visa")
        XCTAssertEqual(inner["encryptedPayload"] as? String, "ZW5jcnlwdGVkLWJsb2I=")
    }
}
