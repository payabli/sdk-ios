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
            entryPoint: named.entry,
            environment: named.environment,

            tokenProvider: {
                await calls.increment()
                return try await Secrets.fetchAccessToken()
            }
        ))

        let fresh = try await auth.invalidateAndRefresh(rejectedToken: "refused-by-the-service")
        XCTAssertFalse(fresh.isEmpty)
        XCTAssertNotEqual(fresh, "refused-by-the-service")
        let held = try await auth.currentAccessToken()
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

    private func makeFlow() throws -> PayabliPayInPaymentFlow {
        PayabliPayInPaymentFlow(
            session: PayabliSession(config: try PayabliConfig(
                entryPoint: named.entry,
                environment: named.environment,

                tokenProvider: { try await Secrets.fetchPaymentMethodAccessToken() }
            ))
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
        let flow = try makeFlow()
        let authorized = try await flow.authorize(request(with: try card()))
        let transId = try XCTUnwrap(
            authorized.transaction?.paymentTransId,
            "authorize returned no paymentTransId: code=\(authorized.code) reason=\(authorized.reason ?? "<nil>")"
        )
        LiveEnvironment.report("PAYABLI_AUTHORIZED env=\(named.name) transId=\(transId) code=\(authorized.code)")

        let voided = try await void(transId, on: flow)
        XCTAssertTrue(voided, "the authorization was left open and needs voiding by hand: \(transId)")
    }

    /// Authorize and capture in one call, so the combined endpoint is exercised as
    /// well as the split one. Voided the same way.
    func testCCaptureThenVoid() async throws {
        let flow = try makeFlow()
        let captured = try await flow.capture(request(with: try card()))
        let transId = try XCTUnwrap(
            captured.transaction?.paymentTransId,
            "capture returned no paymentTransId: code=\(captured.code) reason=\(captured.reason ?? "<nil>")"
        )
        LiveEnvironment.report("PAYABLI_CAPTURED env=\(named.name) transId=\(transId) code=\(captured.code)")

        let voided = try await void(transId, on: flow)
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

        let flow = try makeFlow()
        let authorized = try await flow.authorize(request)
        let transId = try XCTUnwrap(
            authorized.transaction?.paymentTransId,
            "the toggle-off shape was refused: code=\(authorized.code) reason=\(authorized.reason ?? "<nil>")"
        )
        LiveEnvironment.report("PAYABLI_TOGGLE_OFF env=\(named.name) transId=\(transId) code=\(authorized.code)")

        let voided = try await void(transId, on: flow)
        XCTAssertTrue(voided, "left open and needs voiding by hand: \(transId)")
    }

    /// The seam the capture screen's reversal button calls, in the app's own process.
    ///
    /// The button records which payment to reverse and the screen drives the call; this
    /// covers the half that reaches the service, so a screen that stops calling it is the
    /// only way the button can break without this failing.
    @MainActor
    func testEReversingThroughTheScreensOwnSeam() async throws {
        let flow = try makeFlow()
        let captured = try await flow.capture(request(with: try card()))
        let transId = try XCTUnwrap(
            captured.transaction?.paymentTransId,
            "capture returned no paymentTransId: code=\(captured.code)"
        )

        // The reversal button is disabled while a submission is in flight, so a flow that
        // never reports the capture finished would leave it permanently untappable.
        XCTAssertFalse(flow.isSubmitting, "the capture never reported itself finished")

        let outcome = try await PayInFlowHandle(flow).voidTransaction(transId)

        LiveEnvironment.report(
            "PAYABLI_VOID_SEAM env=\(named.name) transId=\(transId) code=\(outcome.code)"
        )
        XCTAssertTrue(
            outcome.code.hasPrefix("A"),
            "the screen's seam did not reverse it, and it needs voiding by hand: \(transId)"
        )
    }

    // MARK: - Void

    /// Reverses a transaction through the SDK's own member, which is what gives this
    /// path product coverage rather than coverage of a request the test wrote itself.
    ///
    /// The transaction id is printed either way, so one left standing can be found.
    private func void(_ transId: String, on flow: PayabliPayInPaymentFlow) async throws -> Bool {
        do {
            let reversed = try await flow.voidTransaction(transId)
            LiveEnvironment.report(
                "PAYABLI_VOID env=\(named.name) transId=\(transId) code=\(reversed.code)"
            )
            // A reversal answers its own approval code rather than a capture's, so the family
            // is what decides. The reason is the service's text and is not reported.
            return reversed.code.hasPrefix("A")
        } catch {
            // The classification and none of its message: that message carries the service's
            // own wording, which can quote what was submitted.
            LiveEnvironment.report(
                "PAYABLI_VOID env=\(named.name) transId=\(transId) failed=\(LoggableError.label(for: error))"
            )
            return false
        }
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
