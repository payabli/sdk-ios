@testable import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow
import XCTest

/// Every money-moving route carries an idempotency key, whether or not the caller supplied one.
///
/// Without one the service recognises no repeat, so a double submit or a retry is a second payment.
/// These cases drive the facade rather than the client, because reserving the key is the facade's job
/// and a client test cannot tell a reserved key from a caller's.
@MainActor
final class PayInIdempotencyTests: XCTestCase {
    // MARK: - The key reaches the wire

    func testACaptureWithNoKeySuppliedStillSendsOne() async throws {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-1")

        _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))

        XCTAssertEqual(transport.sentKeys, ["reserved-1"])
    }

    func testACallersOwnKeyIsSentUnchanged() async throws {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-1")

        _ = try await flow.capture(PayInFixture.request(idempotencyKey: "caller-key"))

        XCTAssertEqual(transport.sentKeys, ["caller-key"], "a reserved key must not replace the caller's")
    }

    func testAnAuthorizationCarriesAKey() async throws {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-2")

        _ = try await flow.authorize(PayInFixture.request(idempotencyKey: nil, cardOnly: true))

        XCTAssertEqual(transport.sentKeys, ["reserved-2"])
    }

    /// The route that passed `nil` before this change, so a retried capture was a second capture.
    func testCapturingAnAuthorizationCarriesAKey() async throws {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-3")

        _ = try await flow.captureAuthorizedTransaction(
            PayabliPayInPaymentFlowAuthorizedRequest(
                transId: "trans-1",
                paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 10)
            )
        )

        XCTAssertEqual(transport.sentKeys, ["reserved-3"])
    }

    func testTwoAttemptsReserveTwoKeys() async throws {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        var minted = 0
        let flow = PayabliPayInPaymentFlow(
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport
        )
        flow.newIdempotencyKey = {
            minted += 1
            return "reserved-\(minted)"
        }

        _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))

        // A second payment is a second key. A retry the caller chooses is the caller's own key, which
        // is the case above.
        XCTAssertEqual(transport.sentKeys, ["reserved-1", "reserved-2"])
    }

    // MARK: - A key that cannot be sent is refused, not dropped

    func testABlankKeyIsRefusedAndNothingIsSent() async {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-1")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: " "))
        })

        // Dropping it silently is the defect: the request would go out with no duplicate protection
        // to a caller who set a key and believes it is protected.
        XCTAssertEqual(
            failure as? PayabliPayInPaymentFlowError,
            .invalidInput("The idempotency key cannot be blank.")
        )
        XCTAssertEqual(transport.count, 0, "nothing is sent")
    }

    func testAKeyThatCannotSitInAHeaderIsRefused() async {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-1")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: "key\r\nX-Injected: v"))
        })

        XCTAssertEqual(
            failure as? PayabliPayInPaymentFlowError,
            .invalidInput("The idempotency key may contain printable ASCII only.")
        )
        XCTAssertEqual(transport.count, 0, "nothing is sent")
    }

    /// `sendableKey` normalises before the header is set, so a caller value with surrounding space
    /// reaches the wire trimmed rather than as it was given.
    func testACallersKeyIsSentTrimmedRatherThanAsGiven() async {
        let transport = RecordingIdempotencyTransport(
            failure: PayabliGenericError(code: .networkError, reason: "Network request failed")
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "unused")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: "  caller-key  "))
        })

        XCTAssertEqual(transport.sentKeys, ["caller-key"])
        XCTAssertNotNil(PayInFixture.interruption(failure), "expected submissionInterrupted, got \(failure)")
    }

    // MARK: - Which failures leave the outcome open

    /// The classification and the failing type reach the caller. The key does not, this SDK minting one
    /// per submission and never handing it out, so there is nothing for a caller to carry.
    func testANetworkFailureLeavesTheOutcomeOpen() async {
        let transport = RecordingIdempotencyTransport(
            failure: PayabliGenericError(code: .networkError, reason: "Network request failed")
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-9")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        guard let interrupted = PayInFixture.interruption(failure) else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(interrupted.code, .networkError)
        // The failing type and none of its message: that message can name a host or quote a body.
        XCTAssertEqual(interrupted.causeType, "PayabliSDKCore.PayabliGenericError")
        XCTAssertEqual(transport.sentKeys, ["reserved-9"], "the key still went out")
    }

    /// A 5xx whose body carries a message decodes into a failure rather than reaching the typed server
    /// error, and that is the path a real 5xx takes. A bodyless `{}` bypasses it, which is what made an
    /// earlier version of this case pass without exercising the classification at all.
    func testAServerFailureReportsTheKey() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"message":"Internal Server Error"}"#.utf8),
            status: 500
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-9")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        guard let interrupted = PayInFixture.interruption(failure) else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(transport.sentKeys.last, "reserved-9")
        XCTAssertEqual(interrupted.code, .serverError)
    }

    /// The same status with an empty body, which the status mapping answers rather than the decoder.
    /// Both shapes have to publish the same classification: a caller branching on the code would
    /// otherwise see a server failure only when the service happened to send a message with it.
    func testABodylessServerFailureReportsTheSameCode() async {
        let transport = RecordingIdempotencyTransport(body: Data(), status: 500)
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-9")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        guard let interrupted = PayInFixture.interruption(failure) else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(transport.sentKeys.last, "reserved-9")
        XCTAssertEqual(interrupted.code, .serverError)
    }

    /// A cancellation is classified as leaving the outcome open, which is what this pins.
    ///
    /// It reaches the classification through an injected error rather than through a cancelled task,
    /// because no production path produces that code: `PayabliService.perform` wraps anything that is
    /// not already a Payabli error, cancellation included, into `networkError`. So this covers the
    /// table's handling of the code and not a route a caller can take to it. Whether a cancelled
    /// request should report cancellation instead is Core's behaviour for every module and is asked
    /// rather than decided here.
    func testACancellationReportsTheKey() async {
        let transport = RecordingIdempotencyTransport(
            failure: PayabliGenericError(code: .userCancelled, reason: "Cancelled")
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-9")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        guard let interrupted = PayInFixture.interruption(failure) else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(transport.sentKeys.last, "reserved-9")
        XCTAssertEqual(interrupted.code, .userCancelled)
    }

    /// An answer the SDK cannot read is the case the key exists for: the payment may well have been
    /// taken, and the only record of it is on the service.
    func testAnUnreadableAnswerReportsTheKey() async {
        let transport = RecordingIdempotencyTransport(body: Data("not json".utf8))
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-9")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        guard let interrupted = PayInFixture.interruption(failure) else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(transport.sentKeys.last, "reserved-9")
        XCTAssertEqual(interrupted.code, .decodingError)
    }

    /// A decline is an answer, so the outcome is known and a retry is a new payment. It arrives on a
    /// successful status with the refusal in the body, which is why the response code decides and not
    /// the status.
    func testADeclineReportsNoKey() async {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.declined)
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-9")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        guard case .transactionFailed = failure as? PayabliPayInPaymentFlowError else {
            return XCTFail("expected transactionFailed, got \(failure)")
        }
        XCTAssertEqual((failure as? any PayabliError)?.code, .paymentDeclined)
        XCTAssertNil(PayInFixture.interruption(failure), "a refusal settles the outcome")
    }

    /// The same successful status carrying a code that is not a refusal: the service could not process
    /// the request rather than declining it, so whether the payment was taken is exactly what is not
    /// known. The sibling separates these two the same way.
    func testAServiceFailureOnASuccessfulStatusReportsTheKey() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"code":"E0001","reason":"Unable to process","explanation":"Try again."}"#.utf8)
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-9")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        guard let interrupted = PayInFixture.interruption(failure) else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(transport.sentKeys.last, "reserved-9")
        XCTAssertEqual(interrupted.code, .serverError)
    }

    /// A repeat the service recognised is what a key produces at all. Reporting it as unknown would
    /// tell a caller to resend the key that provoked it.
    func testARecognisedRepeatReportsNoKey() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"message":"Duplicate request"}"#.utf8),
            status: 409
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-9")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        XCTAssertNil(
            PayInFixture.interruption(failure),
            "a 409 is an answer, not an open outcome"
        )
    }

    /// The same repeat with no body at all, which is the shape the status mapping answers rather than
    /// the decoder. Reporting it as open tells a caller to resend the key the service refuses.
    func testABodylessRecognisedRepeatReportsNoKey() async {
        let transport = RecordingIdempotencyTransport(body: Data(), status: 409)
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-9")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        XCTAssertEqual((failure as? any PayabliError)?.code, .conflict)
        XCTAssertNil(
            PayInFixture.interruption(failure),
            "the service already holds the request, so the outcome is settled"
        )
    }

    /// A decline with no body, which the status mapping answers. Still an answer, so still no key.
    func testABodylessDeclineReportsNoKey() async {
        let transport = RecordingIdempotencyTransport(body: Data(), status: 402)
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-9")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        XCTAssertEqual((failure as? any PayabliError)?.code, .paymentDeclined)
        XCTAssertNil(PayInFixture.interruption(failure), "a decline is an answer, whatever its body")
    }

    /// Refused before the service acted on it, so nothing was taken and the next submit is a fresh
    /// attempt rather than a repeat of this one.
    func testARefusalForTooManyRequestsReportsNoKey() async {
        let transport = RecordingIdempotencyTransport(body: Data(), status: 429)
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-9")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        XCTAssertEqual((failure as? any PayabliError)?.code, .rateLimited)
        XCTAssertNil(PayInFixture.interruption(failure), "the request was refused, not attempted")
    }

    /// A refused credential never reached the operation, so no payment was attempted and no key is
    /// reported. Each of these arrives carrying a message, which is the shape that reaches the body
    /// decoder rather than the status mapping, and the classification has to be the same either way.
    func testARefusedCredentialReportsNoKeyWhateverItsBody() async {
        let expected: [Int: PayabliErrorCode] = [
            401: .tokenExpired,
            403: .permissionDenied,
            410: .sessionBurned
        ]

        for (status, code) in expected {
            let transport = RecordingIdempotencyTransport(
                body: Data(#"{"message":"Refused"}"#.utf8),
                status: status
            )
            let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-9")

            let failure = await PayInFixture.failure(from: {
                _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
            })

            XCTAssertEqual(
                (failure as? any PayabliError)?.code,
                code,
                "a \(status) carrying a message must classify as it does with none"
            )
            XCTAssertNil(
                PayInFixture.interruption(failure),
                "a \(status) never reached the operation, so there is nothing to retry"
            )
        }
    }

    /// A store failure is never wrapped as an attempt whose outcome is open.
    ///
    /// The route sends no key, so a repeat on it is not recognisable and there is nothing for the
    /// wrapping to mean. An unknown store is settled by reading the entry point's stored methods back.
    func testAStoreFailureIsNotWrappedAsAnOpenOutcome() async {
        let transport = RecordingIdempotencyTransport(
            failure: PayabliGenericError(code: .networkError, reason: "Network request failed")
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-9")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.addCard(
                PayabliPayInPaymentFlowCardData(
                    cardNumber: "4111 1111 1111 1111",
                    expiration: "02/27",
                    cardholderName: "John Cassian",
                    cvv: "999",
                    billingZip: "12345"
                ),
                options: PayabliPayInPaymentFlowTokenStorageOptions()
            )
        })

        guard case .submissionInterrupted = failure as? PayabliPayInPaymentFlowError else {
            XCTAssertEqual(transport.sentKeys, [], "the store route sends no key")
            return
        }
        XCTFail("a store failure must not be wrapped as an open outcome")
    }
}
