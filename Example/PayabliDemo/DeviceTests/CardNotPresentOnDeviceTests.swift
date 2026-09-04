@testable import PayabliDemo
@testable import PayabliSDKCore
import PayabliSDKPayInPaymentFlow
import XCTest

/// The card-not-present surface against a live paypoint on real hardware:
/// store a card, authorize against it, and void the authorization.
///
/// The card, the customer and the request shape are the app's own, from
/// `DebugPrefill.json`, `PayInDemoCustomer` and `PayInRequests`. A second set here
/// would be a second thing to keep true of the paypoint, and it was: a request
/// assembled separately went out with no customer at all and was refused.
///
/// These move money in the environment the run names. The void runs whatever the
/// authorization did, so a failure part way through leaves nothing standing.
@MainActor
final class CardNotPresentOnDeviceTests: XCTestCase {
    // Set in setUp, read by every test: the XCTest shape for a fixture that cannot
    // exist at init. Was accepted through the lint baseline until this line moved.
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var named: LiveTarget!

    override func setUp() async throws {
        try await super.setUp()
        named = try LiveEnvironment.named()
        LiveEnvironment.announce(named)
        _ = try await LiveEnvironment.requireAToken()
    }

    /// The rejection path against the real token endpoint: a credential the holder is
    /// told was refused, replaced through the provider, and the stale rejection that
    /// follows answered without asking the provider again.
    ///
    /// Moves no money. The refresh is what every other test here depends on and
    /// nothing else proves it ran, because the app launches holding a token that may
    /// still be valid.
    func testEARejectedTokenIsReplacedOnceAndReused() async throws {
        let calls = ProviderCalls()
        let auth = PayabliAuth(config: try PayabliConfig(
            accessToken: "refused-by-the-service",
            tokenProvider: {
                await calls.increment()
                return try await Secrets.fetchAccessToken()
            },
            entryPoint: named.entry,
            environment: named.environment
        ))

        let fresh = try await auth.invalidateAndRefresh(rejectedToken: "refused-by-the-service")
        XCTAssertFalse(fresh.isEmpty)
        XCTAssertNotEqual(fresh, "refused-by-the-service")
        let held = await auth.currentAccessToken()
        XCTAssertEqual(held, fresh, "the minted token should be the one held")

        // The staggered 401: names a token that has already rotated.
        let again = try await auth.invalidateAndRefresh(rejectedToken: "refused-by-the-service")
        XCTAssertEqual(again, fresh)
        let total = await calls.value
        XCTAssertEqual(total, 1, "the stale rejection should not have called the provider")

        LiveEnvironment.report("PAYABLI_REFRESH env=\(named.name) providerCalls=\(total)")
    }

    /// The test card, from the file the app prefills its form from.
    private func card() throws -> PayabliPayInPaymentFlowCardData {
        let values = try XCTUnwrap(DebugPrefill.values, "DebugPrefill.json is not in the bundle")
        return PayabliPayInPaymentFlowCardData(
            cardNumber: try XCTUnwrap(values.cardNumber).filter(\.isNumber),
            expiration: try XCTUnwrap(values.cardExpiration),
            cardholderName: QAIdentity.current.holderName,
            cvv: try XCTUnwrap(values.cardCvv),
            billingZip: try XCTUnwrap(values.cardZip)
        )
    }

    private func makeFlow() -> PayabliPayInPaymentFlow {
        PayabliPayInPaymentFlow(
            entryPoint: named.entry,
            environment: named.environment,
            accessTokenProvider: { try await Secrets.fetchPaymentMethodAccessToken() }
        )
    }

    /// The request the app's capture screen builds, with this run's card in it.
    ///
    /// `forceCustomerCreation` and the customer number are what a paypoint's
    /// identifier list is satisfied by, and they belong to the app's configuration
    /// rather than to this file.
    private func request(with card: PayabliPayInPaymentFlowCardData) -> PayabliPayInPaymentFlowRequest {
        let configured = PayInRequests.freshCapture(suppliesCustomer: true)
        return PayabliPayInPaymentFlowRequest(
            paymentDetails: configured.paymentDetails,
            paymentMethod: .card(PayabliPayInPaymentFlowCardMethod(data: card)),
            accountId: configured.accountId,
            customerData: configured.customerData,
            ipAddress: configured.ipAddress,
            orderDescription: configured.orderDescription,
            orderId: configured.orderId,
            source: configured.source,
            subdomain: configured.subdomain,
            subscriptionId: configured.subscriptionId,
            idempotencyKey: configured.idempotencyKey,
            achValidation: configured.achValidation,
            forceCustomerCreation: configured.forceCustomerCreation,
            validation: configured.validation
        )
    }

    /// A card is stored and comes back with a token to charge later.
    func testAStoringACardReturnsAToken() async throws {
        let stored = try await makeFlow().addCard(
            try card(),
            options: PayabliPayInPaymentFlowTokenStorageOptions(
                forceCustomerCreation: true,
                customerData: PayInDemoCustomer.customerData
            )
        )

        // The token itself is never printed. `PayabliLogger`'s rules put tokens
        // outside every privacy level, and a stored method is reusable, so a run's
        // output would carry a way to charge the card again.
        let token = try XCTUnwrap(stored.storedMethodId ?? stored.methodReferenceId, "no stored token came back")
        XCTAssertFalse(token.isEmpty)
        LiveEnvironment.report("PAYABLI_STORED_METHOD env=\(named.name) returned=yes")
    }

    /// An authorization is taken and then voided, so nothing settles.
    func testBAuthorizeThenVoid() async throws {
        let authorized = try await makeFlow().authorize(request(with: try card()))
        let transId = try XCTUnwrap(
            authorized.transaction?.paymentTransId,
            "authorize returned no paymentTransId: code=\(authorized.code) reason=\(authorized.reason ?? "<nil>")"
        )
        LiveEnvironment.report("PAYABLI_AUTHORIZED env=\(named.name) transId=\(transId) code=\(authorized.code)")

        let voided = try await void(transId)
        XCTAssertTrue(voided, "the authorization was left open and needs voiding by hand: \(transId)")
    }

    /// Authorize and capture in one call, so the combined endpoint is exercised as
    /// well as the split one. Voided the same way.
    func testCCaptureThenVoid() async throws {
        let captured = try await makeFlow().capture(request(with: try card()))
        let transId = try XCTUnwrap(
            captured.transaction?.paymentTransId,
            "capture returned no paymentTransId: code=\(captured.code) reason=\(captured.reason ?? "<nil>")"
        )
        LiveEnvironment.report("PAYABLI_CAPTURED env=\(named.name) transId=\(transId) code=\(captured.code)")

        let voided = try await void(transId)
        XCTAssertTrue(voided, "the transaction was left standing and needs voiding by hand: \(transId)")
    }

    /// The shape the capture screen sends with "Send a customer number" off: no
    /// customer number, and the payer named by the form's own fields.
    ///
    /// Which of the two is refused decides where a customer-data failure comes
    /// from. A paypoint matching on a number refuses this outright; a paypoint
    /// matching on email takes it, and an empty form is then what fails.
    func testDTheToggleOffShapeNamesAPayerWithoutANumber() async throws {
        let identity = QAIdentity.current
        let configured = PayInRequests.freshCapture(suppliesCustomer: false)
        let payer = PayabliPayInPaymentFlowCustomerData(
            billingEmail: identity.billingEmail,
            firstName: identity.firstName,
            lastName: identity.lastName
        )
        let request = PayabliPayInPaymentFlowRequest(
            paymentDetails: configured.paymentDetails,
            paymentMethod: .card(PayabliPayInPaymentFlowCardMethod(data: try card())),
            customerData: payer,
            orderDescription: configured.orderDescription,
            orderId: configured.orderId,
            source: configured.source,
            idempotencyKey: configured.idempotencyKey,
            forceCustomerCreation: configured.forceCustomerCreation,
            validation: configured.validation
        )

        let authorized = try await makeFlow().authorize(request)
        let transId = try XCTUnwrap(
            authorized.transaction?.paymentTransId,
            "the toggle-off shape was refused: code=\(authorized.code) reason=\(authorized.reason ?? "<nil>")"
        )
        LiveEnvironment.report("PAYABLI_TOGGLE_OFF env=\(named.name) transId=\(transId) code=\(authorized.code)")

        let voided = try await void(transId)
        XCTAssertTrue(voided, "left open and needs voiding by hand: \(transId)")
    }

    // MARK: - Void

    /// `POST /api/v2/MoneyIn/void/{transId}`, direct because the SDK exposes no
    /// void. The transaction id is printed either way, so one left standing can be
    /// found.
    ///
    /// `PayabliEnvironment.baseURL` is the host alone, so the `api` segment belongs
    /// here; without it a void answers 404 and reads as a route that is not there.
    private func void(_ transId: String) async throws -> Bool {
        let token = try await Secrets.fetchPaymentMethodAccessToken()
        var request = URLRequest(
            url: named.environment.baseURL
                .appendingPathComponent("api/v2/MoneyIn/void")
                .appendingPathComponent(transId)
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // The status and the size, not the body: a money-in response carries the
        // processor's whole answer, `paymentTokens.tokenData` among it.
        LiveEnvironment.report(
            "PAYABLI_VOID env=\(named.name) transId=\(transId) status=\(status) bytes=\(data.count)"
        )
        return (200 ..< 300).contains(status)
    }
}

/// Counts provider calls across the actor boundary, so a test can say the stale
/// rejection did not reach the host's endpoint again.
private actor ProviderCalls {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
