import PayabliSDKCore
import PayabliSDKPayInPaymentFlow
import XCTest

/// What this SDK does with the key of an attempt whose outcome nobody knows.
///
/// It holds it, and the next submission of the same payment sends it again, so a repeat is refused
/// rather than taken a second time. The cases here are the bounds on that: which payment counts as
/// the same one, how long the key is worth sending, what drops it, and the one failure the holding
/// itself causes.
@MainActor
final class PayInRetainedKeyTests: XCTestCase {
    // MARK: - An attempt nobody knows the outcome of keeps its key

    /// The case the key exists for. An attempt that was interrupted may already have taken the money,
    /// so the submit after it has to be the same request rather than a new one: the service refuses a
    /// repeat, where a fresh key takes the money again. A payer pressing Submit a second time is the
    /// ordinary way this happens.
    func testARetryAfterAnUnknownOutcomeSendsTheSameKey() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .success(PayInFixture.approved)
            ]
        )
        let flow = PayInFixture.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"])

        _ = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })
        _ = try? await flow.capture(PayInFixture.request(idempotencyKey: nil))

        XCTAssertEqual(
            transport.sentKeys,
            ["reserved-1", "reserved-1"],
            "the retry has to be the same request, or the payer is charged twice"
        )
    }

    /// A different payment is not that retry. Reusing the key there would have the service refuse a
    /// payment the payer meant to make.
    func testADifferentAmountAfterAnUnknownOutcomeSendsANewKey() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .success(PayInFixture.approved)
            ]
        )
        let flow = PayInFixture.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"])

        _ = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })
        _ = try? await flow.capture(PayInFixture.request(idempotencyKey: nil, totalAmount: 99.99))

        XCTAssertEqual(transport.sentKeys, ["reserved-1", "reserved-2"])
    }

    /// An answer settles the attempt, so the next submit is a new payment and carries a new key.
    func testASubmitAfterAKnownOutcomeSendsANewKey() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [.success(PayInFixture.declined), .success(PayInFixture.approved)]
        )
        let flow = PayInFixture.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"])

        _ = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })
        _ = try? await flow.capture(PayInFixture.request(idempotencyKey: nil))

        XCTAssertEqual(
            transport.sentKeys,
            ["reserved-1", "reserved-2"],
            "a refusal is an answer, so the next submit is a second payment"
        )
    }

    /// A caller that supplies its own key is never given the held one.
    func testACallersKeyIsSentEvenAfterAnUnknownOutcome() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .success(PayInFixture.approved)
            ]
        )
        let flow = PayInFixture.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"])

        _ = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })
        _ = try? await flow.capture(PayInFixture.request(idempotencyKey: "caller-key"))

        XCTAssertEqual(transport.sentKeys, ["reserved-1", "caller-key"])
    }

    /// Past the window the service no longer holds the key, so a request carrying it is executed rather
    /// than refused. Sending it there would read as duplicate protection and take the money a second
    /// time, so the held key is dropped and the submission is a new payment.
    func testAHeldKeyIsNotSentOnceTheServiceWouldHaveForgottenIt() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .success(PayInFixture.approved)
            ]
        )
        let clock = TestClock()
        let flow = PayInFixture.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"], clock: clock)

        _ = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })
        clock.advance(by: .seconds(91))
        _ = try? await flow.capture(PayInFixture.request(idempotencyKey: nil))

        XCTAssertEqual(transport.sentKeys, ["reserved-1", "reserved-2"])
    }

    /// Inside the window it is still the same request, so the same key goes out.
    func testAHeldKeyIsStillSentInsideTheWindow() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .success(PayInFixture.approved)
            ]
        )
        let clock = TestClock()
        let flow = PayInFixture.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"], clock: clock)

        _ = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })
        clock.advance(by: .seconds(89))
        _ = try? await flow.capture(PayInFixture.request(idempotencyKey: nil))

        XCTAssertEqual(transport.sentKeys, ["reserved-1", "reserved-1"])
    }

    /// The one failure the key's own handling causes: this SDK chose to repeat the payment, and the
    /// service refused the repeat. A caller did nothing to provoke that and needs to know the earlier
    /// submission reached the service.
    func testARepeatThisSDKSentIsReportedAsRefusedRatherThanAsAConflict() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .status(409)
            ]
        )
        let flow = PayInFixture.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"])

        _ = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })
        let second = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        XCTAssertEqual(second as? PayabliPayInPaymentFlowError, .repeatRefused)
        XCTAssertEqual(transport.sentKeys, ["reserved-1", "reserved-1"])
    }

    /// A conflict on a key the caller chose is not this SDK's doing, so it arrives as the conflict it is.
    func testAConflictOnACallersOwnKeyIsNotReportedAsARepeatThisSDKSent() async {
        let transport = SequencedIdempotencyTransport(outcomes: [.status(409)])
        let flow = PayInFixture.makeFlow(transport: transport, keys: ["unused"])

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: "caller-key"))
        })

        XCTAssertNotEqual(failure as? PayabliPayInPaymentFlowError, .repeatRefused)
        XCTAssertEqual((failure as? any PayabliError)?.code, .conflict)
    }

    /// A retry that never left the device resolves nothing, so the key it was going to send is still the
    /// one the next submission needs. Dropping it here is what turns a corrected retry into a second
    /// payment.
    func testAFailureBeforeAnythingIsSentKeepsTheHeldKey() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .success(PayInFixture.approved)
            ]
        )
        let flow = PayInFixture.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"])

        _ = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })
        _ = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: "   "))
        })
        _ = try? await flow.capture(PayInFixture.request(idempotencyKey: nil))

        XCTAssertEqual(
            transport.sentKeys,
            ["reserved-1", "reserved-1"],
            "the blank key refusal sent nothing, so the held key is still the one to send"
        )
    }

    /// Two payments of equal value are not the same payment. What tells them apart is what the caller
    /// already sets to tell them apart.
    func testTwoPaymentsOfEqualValueDoNotShareAHeldKey() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .success(PayInFixture.approved)
            ]
        )
        let flow = PayInFixture.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"])

        _ = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil, orderId: "order-1"))
        })
        _ = try? await flow.capture(PayInFixture.request(idempotencyKey: nil, orderId: "order-2"))

        XCTAssertEqual(transport.sentKeys, ["reserved-1", "reserved-2"])
    }

    /// The request body trims an order before sending it, so two submissions differing only in space
    /// around it are one payment on the wire. Comparing them as the caller wrote them read that as two
    /// and minted a second key, which is the protection removing itself.
    func testAnOrderDifferingOnlyInSpaceIsTheSamePayment() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .success(PayInFixture.approved)
            ]
        )
        let flow = PayInFixture.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"])

        _ = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil, orderId: "order-1"))
        })
        _ = try? await flow.capture(PayInFixture.request(idempotencyKey: nil, orderId: "  order-1  "))

        XCTAssertEqual(transport.sentKeys, ["reserved-1", "reserved-1"])
    }

    /// Two payments can each end without an answer. A single slot let the second erase the first's key,
    /// so retrying the first minted a fresh one and could charge it twice.
    func testTwoPaymentsWithUnknownOutcomesEachKeepTheirOwnKey() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .success(PayInFixture.approved)
            ]
        )
        let flow = PayInFixture.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2", "reserved-3"])

        _ = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil, orderId: "order-a"))
        })
        _ = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil, orderId: "order-b"))
        })
        _ = try? await flow.capture(PayInFixture.request(idempotencyKey: nil, orderId: "order-a"))

        XCTAssertEqual(
            transport.sentKeys,
            ["reserved-1", "reserved-2", "reserved-1"],
            "the first payment's key survives the second payment's unknown outcome"
        )
    }

    /// An answer answers for the payment, not for the key that carried it. A caller's own key
    /// succeeding means that payment happened, so a key still held for it would charge a second time.
    func testACallersKeySucceedingOnAHeldPaymentDropsTheHeldKey() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .success(PayInFixture.approved),
                .success(PayInFixture.approved)
            ]
        )
        let flow = PayInFixture.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"])

        _ = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })
        _ = try? await flow.capture(PayInFixture.request(idempotencyKey: "caller-key"))
        _ = try? await flow.capture(PayInFixture.request(idempotencyKey: nil))

        XCTAssertEqual(transport.sentKeys, ["reserved-1", "caller-key", "reserved-2"])
    }

    /// A refusal of the credential says nothing about the payment, so it does not resolve the attempt
    /// whose outcome nobody knows. Reading every decoded failure as an answer dropped the key those had
    /// not resolved, and the next corrected submission charged again.
    func testARefusedCredentialOnARetryKeepsTheHeldKey() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .response(401, Data(#"{"message":"Unauthorized"}"#.utf8)),
                .success(PayInFixture.approved)
            ]
        )
        let flow = PayInFixture.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"])

        for _ in 0 ..< 2 {
            _ = await PayInFixture.failure(from: {
                _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
            })
        }
        _ = try? await flow.capture(PayInFixture.request(idempotencyKey: nil))

        XCTAssertEqual(
            transport.sentKeys,
            ["reserved-1", "reserved-1", "reserved-1"],
            "a refused credential resolves nothing, so the key is still the one to send"
        )
    }
}
