import XCTest
import PayabliSDKCore
@testable import PayabliSDKPayIn

/// End-to-end tokenization tests against `api-sandbox.payabli.com` (PRD §12.2).
/// Auto-skipped when credentials are not supplied — see IntegrationTestCase.
final class TokenizationIntegrationTests: IntegrationTestCase {

    func testTokenizeVisa() async throws {
        let creds = try sandboxCreds()
        let config = try sandboxConfig()
        let service = PayabliService(environment: .sandbox)
        let auth = PayabliAuth(config: config)
        let client = TokenStorageClient(service: service, auth: auth)

        let request = CardTokenizationRequest(
            customerData: CustomerDataBlock(customerId: creds.customerId),
            entryPoint: config.entryPoint,
            paymentMethod: CardTokenizationPayload(
                cardnumber: "4111111111111111",
                cardexp: "1230",
                cardcvv: "123",
                cardHolder: "Integration Test",
                cardzip: "90210"
            )
        )
        let token = try await client.tokenizeCard(request)
        XCTAssertFalse(token.isEmpty)
    }

    func testTokenizeACH() async throws {
        let creds = try sandboxCreds()
        let config = try sandboxConfig()
        let service = PayabliService(environment: .sandbox)
        let auth = PayabliAuth(config: config)
        let client = TokenStorageClient(service: service, auth: auth)

        let request = ACHTokenizationRequest(
            customerData: CustomerDataBlock(customerId: creds.customerId),
            entryPoint: config.entryPoint,
            paymentMethod: ACHTokenizationPayload(
                achAccount: "123456789",
                achRouting: "021000021",
                achAccountType: .checking,
                achHolder: "Integration Test",
                achHolderType: .personal
            )
        )
        let token = try await client.tokenizeACH(request)
        XCTAssertFalse(token.isEmpty)
    }
}
