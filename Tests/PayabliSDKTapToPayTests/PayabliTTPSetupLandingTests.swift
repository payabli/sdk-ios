@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

#if canImport(PayabliCardReaderCore)
    import PayabliCardReaderCore
#endif

/// Where `initialize` leaves the session when setting the device up fails, read through the facade a
/// host calls.
@available(iOS 16.7, *)
@MainActor
final class PayabliTTPSetupLandingTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    /// Each way setting the device up fails reaches the state its remedy repairs, and none of them
    /// asks for the device to be set up again.
    func testAFailedSetupLandsWhereItsRemedyRepairsIt() async throws {
        let cases: [(PayabliErrorType, PayabliTTPSessionState)] = [
            (.deviceKeyUnavailable, .failed(reason: .deviceKeyUnavailable)),
            (.sdkInternalError, .failed(reason: .sdkInternalError)),
            (.decodingError, .failed(reason: .sdkInternalError)),
            (.deviceSetupUnavailable, .failed(reason: .serviceUnavailable)),
            (.deviceSetupUnsupported, .failed(reason: .deviceIneligible)),
            (.deviceSetupNotConfigured, .failed(reason: .configurationRejected)),
            (.deviceIdentityUnavailable, .failed(reason: .deviceIneligible))
        ]
        for (type, expected) in cases {
            let (ttp, _, attestation) = try makeTTP()
            attestation.attestResult = .failure(TapToPayError(type: type, reason: "x", detail: nil))

            do {
                try await ttp.initialize()
                XCTFail("initialize proceeded past \(type)")
            } catch {
                XCTAssertEqual((error as? TapToPayError)?.type, type, "\(error)")
            }
            XCTAssertEqual(ttp.sessionState, expected, "\(type)")
        }
    }

    /// A key check that cannot reach Apple's attestation service stops, keeping the binding, and the
    /// same call may work later.
    func testAKeyCheckThatCannotReachAppleLandsOnServiceUnavailable() async throws {
        let (ttp, _, attestation) = try makeTTP()
        attestation.readFailure = TapToPayError(type: .deviceSetupUnavailable, reason: "x", detail: nil)

        do {
            try await ttp.initialize()
            XCTFail("initialize proceeded past a key check that could not reach Apple")
        } catch {
            XCTAssertEqual((error as? TapToPayError)?.type, .deviceSetupUnavailable, "\(error)")
        }
        XCTAssertEqual(ttp.sessionState, .failed(reason: .serviceUnavailable))
    }

    /// An activation that could not be signed lands by its cause, as `initialize` does, because no
    /// activation code repairs a device that cannot sign.
    func testAnActivationThatCannotBeSignedLandsByItsCause() async throws {
        let cases: [(PayabliErrorType, PayabliTTPSessionState)] = [
            (.deviceKeyUnavailable, .failed(reason: .deviceKeyUnavailable)),
            (.deviceSetupNotConfigured, .failed(reason: .configurationRejected)),
            (.deviceSetupUnsupported, .failed(reason: .deviceIneligible)),
            (.deviceSetupUnavailable, .failed(reason: .serviceUnavailable)),
            (.deviceSetupRequired, .failed(reason: .deviceSetupRequired)),
            (.sdkInternalError, .failed(reason: .sdkInternalError))
        ]
        for (type, expected) in cases {
            let (ttp, _, attestation) = try makeTTP()
            attestation.pendingRegistration = "dev_e"
            _ = try? await ttp.initialize()
            attestation.activationResult = .failure(
                ActivationSigningFailed(hostError: TapToPayError(type: type, reason: "x", detail: nil))
            )

            do {
                try await ttp.activateDevice(activationCode: "123456")
                XCTFail("activation succeeded past \(type)")
            } catch {
                XCTAssertEqual((error as? TapToPayError)?.type, type, "\(type): \(error)")
            }
            XCTAssertEqual(ttp.sessionState, expected, "\(type)")
        }
    }

    /// A setup failure met while activating, outside the signature, lands by its code as well: a
    /// store that cannot be read is not repaired by an activation code.
    func testASetupFailureWhileActivatingLandsByItsCode() async throws {
        let cases: [(PayabliErrorType, PayabliTTPSessionState)] = [
            (.deviceKeyUnavailable, .failed(reason: .deviceKeyUnavailable)),
            (.deviceSetupNotConfigured, .failed(reason: .configurationRejected)),
            (.sdkInternalError, .failed(reason: .sdkInternalError))
        ]
        for (type, expected) in cases {
            let (ttp, _, attestation) = try makeTTP()
            attestation.pendingRegistration = "dev_e"
            _ = try? await ttp.initialize()
            attestation.activationResult = .failure(TapToPayError(type: type, reason: "x", detail: nil))

            do {
                try await ttp.activateDevice(activationCode: "123456")
                XCTFail("activation succeeded past \(type)")
            } catch {
                XCTAssertEqual((error as? TapToPayError)?.type, type, "\(type): \(error)")
            }
            XCTAssertEqual(ttp.sessionState, expected, "\(type)")
        }
    }

    /// A request whose assertion cannot be produced lands by its code: a key lost after the check
    /// passed is set up again, not reported as an SDK defect.
    func testAConfigurationRequestThatCannotBeSignedLandsByItsCode() async throws {
        let cases: [(PayabliErrorType, PayabliTTPSessionState)] = [
            (.deviceSetupRequired, .failed(reason: .deviceSetupRequired)),
            (.deviceSetupUnsupported, .failed(reason: .deviceIneligible)),
            (.deviceSetupUnavailable, .failed(reason: .serviceUnavailable)),
            (.sdkInternalError, .failed(reason: .sdkInternalError))
        ]
        for (type, expected) in cases {
            let (ttp, _, attestation) = try makeTTP()
            attestation.bindings = ["e": "dev_e"]
            attestation.assertionFailure = TapToPayError(type: type, reason: "x", detail: nil)

            do {
                try await ttp.initialize()
                XCTFail("initialize proceeded past \(type)")
            } catch {
                XCTAssertEqual((error as? TapToPayError)?.type, type, "\(type): \(error)")
            }
            XCTAssertEqual(ttp.sessionState, expected, "\(type)")
        }
    }

    /// A withdrawn setup is asked again, which is safe.
    func testAWithdrawnSetupLandsOnIdle() async throws {
        let (ttp, _, attestation) = try makeTTP()
        attestation.attestResult = .failure(CancellationError())

        do {
            try await ttp.initialize()
            XCTFail("initialize proceeded past a withdrawn setup")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(ttp.sessionState, .idle)
    }

    /// A device the service no longer recognises during activation is set up again, the same answer
    /// `initialize` gives.
    func testActivationRefusedForASetupThatEndedLandsOnDeviceSetupRequired() async throws {
        let failures: [Error] = [
            PayabliTTPError.attestationRevoked(reason: "x"),
            ActivationRegistrationChanged()
        ]
        for failure in failures {
            let (ttp, _, attestation) = try makeTTP()
            attestation.pendingRegistration = "dev_e"
            _ = try? await ttp.initialize()
            XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_e"), "\(failure)")
            attestation.activationResult = .failure(failure)

            do {
                try await ttp.activateDevice(activationCode: "123456")
                XCTFail("activation succeeded past \(failure)")
            } catch {
                XCTAssertEqual((error as? TapToPayError)?.type, .deviceSetupRequired, "\(failure): \(error)")
            }
            XCTAssertEqual(ttp.sessionState, .failed(reason: .deviceSetupRequired), "\(failure)")
        }
    }

    // MARK: - A reader's own failures

    /// A network failure while the code is being activated keeps the network's
    /// own answer — the attempt can be retried when the connection returns — and
    /// the session still waits for the code.
    func testANetworkFailureWhileActivatingKeepsTheNetworksAnswerAndTheWait() async throws {
        let (ttp, _, attestation) = try makeTTP()
        attestation.pendingRegistration = "dev_e"
        _ = try? await ttp.initialize()
        XCTAssertEqual(
            ttp.sessionState,
            .pendingActivation(activationId: "dev_e"),
            "the fixture itself is broken if this fails"
        )
        attestation.activationFailuresFirst = [URLError(.timedOut)]

        do {
            try await ttp.activateDevice(activationCode: "123456")
            XCTFail("activation succeeded past a network failure")
        } catch {
            let host = TapToPayErrorTranslation.hostError(for: error)
            XCTAssertEqual((host as? TapToPayError)?.type, .networkError, "\(error)")
        }
        XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_e"))
    }

    /// A device the platform refuses needs no wire to say so: the refusal is the
    /// device's own, and the session lands where only a different device repairs it.
    func testAnUnsupportedDeviceReportsItsOwnCodeAndLandsIneligible() async throws {
        let reader = FiservCardReader()
        reader.setPlatformSupportSource(false)
        let (ttp, _) = try makeTTP(provider: reader)

        do {
            try await ttp.initialize()
            XCTFail("initialize proceeded on a device the platform refuses")
        } catch {
            let host = TapToPayErrorTranslation.hostError(for: error)
            XCTAssertEqual((host as? TapToPayError)?.type, .deviceHardwareUnsupported, "\(error)")
        }
        XCTAssertEqual(ttp.sessionState, .failed(reason: .deviceIneligible))
    }

    #if canImport(PayabliCardReaderCore)
        /// The vendor's refusal of the handset is the device's own refusal: it
        /// reports the refusal's code and lands the device ineligible.
        func testAVendorRefusalOfTheDeviceReportsItsOwnCodeAndLandsIneligible() async throws {
            let vendored = FiservTTPCardReaderError(
                title: "Setup failed",
                localizedDescription: "the vendor refused the device",
                failureReason: #"{"responseCode":"677","responseText":"Declined"}"#
            )
            let (ttp, _) = try makeReaderBackedTTP(vendored: vendored)

            do {
                try await ttp.initialize()
                XCTFail("initialize proceeded past a vendor refusal of the device")
            } catch {
                let host = TapToPayErrorTranslation.hostError(for: error)
                XCTAssertEqual((host as? TapToPayError)?.type, .readerDeviceRefused, "\(error)")
            }
            XCTAssertEqual(ttp.sessionState, .failed(reason: .deviceIneligible))
        }

        /// A vendor failure that is not a refusal of the handset is the reader's
        /// own: it reports the reader's code, and the session waits for a reader.
        func testAVendorFailureOfTheReaderReportsItsOwnCodeAndLandsWaiting() async throws {
            let vendored = FiservTTPCardReaderError(
                title: "Setup failed",
                localizedDescription: "the reader could not be started",
                failureReason: #"{"responseCode":"999","responseText":"Unreachable"}"#
            )
            let (ttp, _) = try makeReaderBackedTTP(vendored: vendored)

            do {
                try await ttp.initialize()
                XCTFail("initialize proceeded past a reader that could not be started")
            } catch {
                let host = TapToPayErrorTranslation.hostError(for: error)
                XCTAssertEqual((host as? TapToPayError)?.type, .readerUnavailable, "\(error)")
            }
            XCTAssertEqual(ttp.sessionState, .failed(reason: .serviceUnavailable))
        }
    #endif

    private func makeTTP() throws -> (PayabliTTP, MockTapToPayProvider, MockDeviceAttestationService) {
        let config = try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" })
        let provider = MockTapToPayProvider()
        let attestation = MockDeviceAttestationService()
        let ttp = PayabliTTP(
            config: config,
            provider: provider,
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        return (ttp, provider, attestation)
    }

    /// The same TTP on a chosen provider, for a reader the mock cannot stand in for.
    private func makeTTP(provider: some TapToPayProvider) throws -> (PayabliTTP, MockDeviceAttestationService) {
        let config = try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" })
        let attestation = MockDeviceAttestationService()
        let ttp = PayabliTTP(
            config: config,
            provider: provider,
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        return (ttp, attestation)
    }

    #if canImport(PayabliCardReaderCore)
        /// A TTP on a real reader whose setup throws `vendored`, so the vendor's own
        /// failures reach the classify path. The binding is warm and `/config` answers a
        /// complete envelope, so the only moving part is the reader.
        private func makeReaderBackedTTP(vendored: Error) throws -> (PayabliTTP, FiservCardReader) {
            StubURLProtocol.handler = Self.readerConfigHandler
            let config = try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" })
            let attestation = MockDeviceAttestationService()
            attestation.bindings = ["e": "dev_e"]
            let reader = FiservCardReader()
            reader.setPlatformSupportSource(true)
            reader.setLinkStateSource(LinkedStub())
            reader.setReaderFactory { _ in ThrowingReaderSetup(failure: vendored) }
            let ttp = PayabliTTP(
                config: config,
                provider: reader,
                attestation: attestation,
                retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
                session: StubURLProtocol.makeSession()
            )
            return (ttp, reader)
        }

        /// Answers `/config` with a complete credentials envelope, the shape a real
        /// reader is configured from.
        private static let readerConfigHandler: StubURLProtocol.Handler = { request in
            let credentials: [String: String] = [
                "secretKey": "s",
                "apiKey": "a",
                "merchantId": "m",
                "terminalId": "t",
                "environment": "sandbox",
                "currencyCode": "USD",
                "appleTtpMerchantId": "apple-m",
                "merchantName": "name",
                "merchantCategoryCode": "code",
                "terminalProfileId": "profile"
            ]
            let body: [String: Any] = [
                "responseCode": 1,
                "isSuccess": true,
                "responseData": ["credentials": credentials]
            ]
            let data = try JSONSerialization.data(withJSONObject: body)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!,
                data
            )
        }
    #endif
}

/// Linked throughout, so a reader path that reaches the terms question runs on
/// without a sheet. A throwing setup never gets that far, but the facade is
/// given a reader whose every answer is stable.
private final class LinkedStub: AccountLinking {
    func isAccountLinked() async throws -> Bool {
        true
    }

    func linkAccount() async throws {}
}

/// A reader whose session never opens: it throws the vendor's own failure, the
/// way a reader that refused the handset or could not be reached does.
private final class ThrowingReaderSetup: ReaderSetup {
    private let failure: Error

    init(failure: Error) {
        self.failure = failure
    }

    func requestSessionToken() async throws {
        throw failure
    }

    func isAccountLinked() async throws -> Bool {
        true
    }

    func linkAccount() async throws {}

    func initializeSession(onReaderEvent _: @escaping @MainActor (TapToPayReaderEvent) -> Void) async throws {
        throw failure
    }
}
