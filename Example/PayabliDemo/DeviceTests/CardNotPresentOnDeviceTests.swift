@testable import PayabliDemo
import PayabliSDKCore
import PayabliSDKPayInPaymentFlow
import XCTest

/// The card-not-present surface against a live paypoint on real hardware:
/// store a card, authorize against it, and void the authorization.
///
/// These move money in the environment the run names. The void is what keeps an
/// authorization from sitting open afterwards, and it runs whatever the
/// authorization did, so a failure part way through does not leave one behind.
@MainActor
final class CardNotPresentOnDeviceTests: XCTestCase {
    private var named: (environment: PayabliEnvironment, entry: String, name: String)!

    /// The card every environment's test data accepts, from the demo's own
    /// prefill fixture.
    private static let card = PayabliPayInPaymentFlowCardData(
        cardNumber: "4111111111111111",
        expiration: "07/30",
        cardholderName: "Name On Card Test1",
        cvv: "999",
        billingZip: "22039"
    )

    /// Small enough that a settled one is noise if a void ever fails.
    private static let amount = 1.00

    override func setUp() async throws {
        try await super.setUp()
        named = try LiveEnvironment.named()
        LiveEnvironment.announce(named)
        _ = try await LiveEnvironment.requireAToken()
    }

    private func makeFlow() -> PayabliPayInPaymentFlow {
        PayabliPayInPaymentFlow(
            entryPoint: named.entry,
            environment: named.environment,
            accessTokenProvider: { try await Secrets.fetchPaymentMethodAccessToken() }
        )
    }

    /// A card is stored and comes back with a token to charge later.
    func testAStoringACardReturnsAToken() async throws {
        let stored = try await makeFlow().addCard(Self.card)

        let token = try XCTUnwrap(stored.storedMethodId ?? stored.methodReferenceId, "no stored token came back")
        XCTAssertFalse(token.isEmpty)
        print("PAYABLI_STORED_METHOD env=\(named.name) token=\(token)")
    }

    /// An authorization is taken and then voided, so nothing settles.
    func testBAuthorizeThenVoid() async throws {
        let flow = makeFlow()
        let request = PayabliPayInPaymentFlowRequest(
            paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: Self.amount),
            paymentMethod: .card(PayabliPayInPaymentFlowCardMethod(data: Self.card)),
            orderDescription: "PLA-2509 device check",
            idempotencyKey: UUID().uuidString
        )

        let authorized = try await flow.authorize(request)
        let transId = try XCTUnwrap(
            authorized.transaction?.paymentTransId,
            "authorize returned no paymentTransId: code=\(authorized.code) reason=\(authorized.reason ?? "<nil>")"
        )
        print("PAYABLI_AUTHORIZED env=\(named.name) transId=\(transId) code=\(authorized.code)")

        let voided = try await void(transId)
        XCTAssertTrue(voided, "the authorization was left open and needs voiding by hand: \(transId)")
    }

    /// The whole card-present-less path in one call, so the combined endpoint is
    /// exercised as well as the split one. Voided the same way.
    func testCCaptureThenVoid() async throws {
        let flow = makeFlow()
        let request = PayabliPayInPaymentFlowRequest(
            paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: Self.amount),
            paymentMethod: .card(PayabliPayInPaymentFlowCardMethod(data: Self.card)),
            orderDescription: "PLA-2509 device check",
            idempotencyKey: UUID().uuidString
        )

        let captured = try await flow.capture(request)
        let transId = try XCTUnwrap(
            captured.transaction?.paymentTransId,
            "capture returned no paymentTransId: code=\(captured.code) reason=\(captured.reason ?? "<nil>")"
        )
        print("PAYABLI_CAPTURED env=\(named.name) transId=\(transId) code=\(captured.code)")

        let voided = try await void(transId)
        XCTAssertTrue(voided, "the transaction was left standing and needs voiding by hand: \(transId)")
    }

    // MARK: - Void

    /// `POST /api/v2/MoneyIn/void/{transId}`, direct rather than through the SDK,
    /// which exposes no void. The transaction id is printed either way, so one
    /// left open can be found.
    private func void(_ transId: String) async throws -> Bool {
        let token = try await Secrets.fetchPaymentMethodAccessToken()
        var request = URLRequest(
            url: named.environment.baseURL.appendingPathComponent("v2/MoneyIn/void/\(transId)")
        )
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "requestToken")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(decoding: data, as: UTF8.self)
        print("PAYABLI_VOID env=\(named.name) transId=\(transId) status=\(status) body=\(body.prefix(200))")
        return (200 ..< 300).contains(status)
    }
}
