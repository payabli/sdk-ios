import XCTest
import PayabliSDKCore
@testable import PayabliSDKPayIn

/// Integration tests for card-not-present payment processing (PRD §12.2, §9.3A–C).
/// Auto-skipped when credentials are not supplied.
final class GetpaidIntegrationTests: IntegrationTestCase {

    func testApprovedCardPayment() async throws {
        let creds = try sandboxCreds()
        let config = try sandboxConfig()
        let service = PayabliService(environment: .sandbox)
        let auth = PayabliAuth(config: config)
        let client = GetpaidClient(service: service, auth: auth)

        let payload = CardTokenizationPayload(
            cardnumber: "4111111111111111",
            cardexp: "1230",
            cardcvv: "123",
            cardHolder: "Integration Test",
            cardzip: "90210"
        )
        let request = PayabliPaymentRequest(totalAmount: 1.00)
        let result = try await client.chargeCard(
            payload: payload,
            request: request,
            customerId: creds.customerId,
            entryPoint: config.entryPoint
        )
        XCTAssertTrue(result.responseCode.hasPrefix("A"))
        XCTAssertFalse(result.paymentTransId.isEmpty)
    }

    func testDeclinedCardPayment() async throws {
        let creds = try sandboxCreds()
        let config = try sandboxConfig()
        let service = PayabliService(environment: .sandbox)
        let auth = PayabliAuth(config: config)
        let client = GetpaidClient(service: service, auth: auth)

        // Amount 0.05 is a common sandbox decline trigger; confirm with your backend.
        let payload = CardTokenizationPayload(
            cardnumber: "4111111111111111",
            cardexp: "1230",
            cardcvv: "123",
            cardHolder: "Integration Test Decline",
            cardzip: "90210"
        )
        let request = PayabliPaymentRequest(totalAmount: 0.05)
        do {
            _ = try await client.chargeCard(
                payload: payload,
                request: request,
                customerId: creds.customerId,
                entryPoint: config.entryPoint
            )
            // If sandbox approves 0.05, skip rather than fail — trigger depends on backend config.
            throw XCTSkip("Sandbox did not decline 0.05 — adjust the trigger amount")
        } catch PayabliPaymentError.decline(let err) {
            XCTAssertTrue(err.rawCode.hasPrefix("D"))
        }
    }
}
