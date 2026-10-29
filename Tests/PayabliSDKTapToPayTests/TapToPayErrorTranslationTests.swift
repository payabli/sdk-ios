@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// What a host is handed for each failure the SDK raises: always a `TapToPayError`, under the catalog entry
/// for its cause, still naming the payment it belongs to.
@available(iOS 16.7, *)
final class TapToPayErrorTranslationTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - Every case reaches its catalog code

    func testEveryCaseReachesAHostUnderItsCatalogCode() {
        for error in Self.allSamples {
            let host = TapToPayErrorTranslation.hostError(for: error)
            guard let host = host as? TapToPayError else {
                XCTFail("\(error) reached a host as \(type(of: host))")
                continue
            }
            XCTAssertEqual(host.type, Self.expectedType(of: error), "Wrong entry for \(error)")
            XCTAssertEqual(host.code, Self.expectedType(of: error).number)
        }
    }

    // MARK: - Reason and detail

    func testACardPresentCaseCarriesItsCodesTextAsTheReasonAndItsOwnWordsAsTheDetail() throws {
        let host = try translated(PayabliTTPError.nfcFailed(reason: "card moved away"))
        XCTAssertEqual(host.reason, PayabliErrorType.tapNotCompleted.message)
        XCTAssertEqual(host.detail, "card moved away")
    }

    func testADismissedSheetIsACancellationByThePerson() throws {
        let prefix = PayabliTTPError.cancellationReasonPrefix
        XCTAssertEqual(try translated(PayabliTTPError.nfcFailed(reason: "\(prefix) dismissed")).type, .userCancelled)
        XCTAssertEqual(
            try translated(PayabliTTPError.readerSetupFailed(reason: "\(prefix) dismissed")).type,
            .userCancelled
        )
        XCTAssertEqual(
            try translated(PayabliTTPError.readerUnavailable(reason: "\(prefix) dismissed")).type,
            .userCancelled
        )
    }

    /// The catalog's sentence and nothing else: no host-facing text names the field that was blank.
    func testBlankReaderCredentialsReachAHostAsTheCatalogEntryAndNameNoField() throws {
        let host = try translated(PayabliTTPError.readerCredentialsUnusable)
        XCTAssertEqual(host.type, .readerCredentialsUnusable)
        XCTAssertEqual(host.code, 3010)
        XCTAssertEqual(host.category, .configuration)
        XCTAssertEqual(host.reason, "The card reader's configuration is incomplete.")
        XCTAssertNil(host.detail)

        let nsError = host.toPayabliNSError()
        XCTAssertEqual(nsError.code, 3010)
        let shown = [host.errorDescription ?? "", nsError.localizedDescription, "\(nsError.userInfo)", "\(host)"]
        for text in shown {
            for key in FiservCardReader.requiredCredentialKeys {
                XCTAssertFalse(text.contains(key), "\(key) in \(text)")
            }
        }
    }

    func testAnEmptyReasonIsNeverOfferedAsTheDetail() throws {
        XCTAssertNil(try translated(PayabliTTPError.attestationFailed(reason: "")).detail)
        XCTAssertNil(try translated(PayabliTTPError.nfcFailed(reason: "  \n")).detail)
    }

    func testACaseWithNoTextCarriesNoDetail() throws {
        XCTAssertNil(try translated(PayabliTTPError.devicePendingActivation).detail)
    }

    func testATransportFailureKeepsItsCodeReasonAndDetail() throws {
        let host = try translated(
            PayabliGenericError(type: .tokenProviderFailed, reason: "no usable token", detail: "provider threw")
        )
        XCTAssertEqual(host.type, .tokenProviderFailed)
        XCTAssertEqual(host.reason, "no usable token")
        XCTAssertEqual(host.detail, "provider threw")
        XCTAssertEqual(host.capture, .notCharged)
        XCTAssertNil(host.paymentTransId)
        XCTAssertNil(host.retryAfter)
    }

    func testATransportFailureKeepsTheWaitTheServiceAskedFor() throws {
        struct Throttled: PayabliError, PayabliRetryAfter {
            let type = PayabliErrorType.rateLimited
            let reason = "Too many requests"
            let detail: String? = nil
            let retryAfter: TimeInterval? = 30
        }
        let host = try translated(Throttled())
        XCTAssertEqual(host.type, .rateLimited)
        XCTAssertEqual(host.retryAfter, 30)
        XCTAssertEqual((host as PayabliRetryAfter).retryAfter, 30)
        XCTAssertEqual(host.toPayabliNSError().userInfo["retryAfter"] as? TimeInterval, 30)
    }

    func testACoreErrorKeepsEverythingItShowsAfterItsReason() throws {
        struct Refused: PayabliError {
            let type = PayabliErrorType.validation
            let reason = "Bad request"
            let detail: String? = "One field is wrong"
            var errorDescription: String? {
                "Bad request · One field is wrong · zip: must be five digits"
            }
        }
        let host = try translated(Refused())
        XCTAssertEqual(host.detail, "One field is wrong · zip: must be five digits")
        XCTAssertTrue(host.localizedDescription.contains("zip: must be five digits"), host.localizedDescription)
    }

    // MARK: - A charge

    func testOnceTheCardWasAskedForACodeSayingNothingWasSentIsAnUnconfirmedOutcome() throws {
        for refused in [PayabliErrorType.validation, .sdkInternalError] {
            let host = try XCTUnwrap(
                TapToPayErrorTranslation.hostError(
                    for: PayabliGenericError(type: refused, reason: "refused", detail: "the service's words"),
                    chargeOf: "TXN-9",
                    askedForCard: true
                ) as? TapToPayError
            )
            XCTAssertEqual(host.type, .paymentOutcomeUnknown, "\(refused)")
            XCTAssertEqual(host.reason, PayabliErrorType.paymentOutcomeUnknown.message, "\(refused)")
            XCTAssertEqual(host.detail, "the service's words", "\(refused)")
            XCTAssertEqual(host.paymentTransId, "TXN-9")
            XCTAssertEqual(host.capture, .unknown)
        }
    }

    func testBeforeTheCardWasAskedForAFailureKeepsItsCodeAndChargedNothing() throws {
        let host = try XCTUnwrap(
            TapToPayErrorTranslation.hostError(
                for: PayabliGenericError(type: .validation, reason: "refused"),
                chargeOf: "TXN-9",
                askedForCard: false
            ) as? TapToPayError
        )
        XCTAssertEqual(host.type, .validation)
        XCTAssertEqual(host.reason, "refused")
        XCTAssertEqual(host.paymentTransId, "TXN-9")
        XCTAssertEqual(host.capture, .notCharged)
    }

    func testAFailureNamingItsOwnPaymentKeepsItsOwnCapture() throws {
        let host = try XCTUnwrap(
            TapToPayErrorTranslation.hostError(
                for: PayabliTTPError.cardDeclined(paymentTransId: "TXN-1"),
                chargeOf: "TXN-9",
                askedForCard: true
            ) as? TapToPayError
        )
        XCTAssertEqual(host.type, .cardDeclined)
        XCTAssertEqual(host.paymentTransId, "TXN-1")
        XCTAssertEqual(host.capture, .notCharged)
    }

    func testACancelledChargeStaysACancellation() {
        let host = TapToPayErrorTranslation.hostError(for: CancellationError(), chargeOf: "TXN-9", askedForCard: true)
        XCTAssertTrue(host is CancellationError, "got \(host)")
    }

    // MARK: - Codes

    func testARejectedCredentialAndARefusedReaderAreToldApartByTheirCode() throws {
        let credential = try translated(PayabliTTPError.tokenExpired)
        let reader = try translated(PayabliTTPError.readerOSVersionNotSupported())
        XCTAssertNotEqual(credential.code, reader.code)
        XCTAssertEqual(credential.category, .credential)
        XCTAssertEqual(reader.category, .device)
    }

    /// Every card-present code is produced by some cause on this platform, or is named here with the reason it
    /// is not.
    func testEveryCardPresentCodeThisPlatformCanProduceHasACause() {
        let fromTheTable = Set(Self.allSamples.map { Self.expectedType(of: $0) })
            .union([.userCancelled, .paymentOutcomeUnknown])
        let fromActivation = Set(
            ActivationRefusalsTests.serviceRefusals.map { ActivationRefusals.catalogType(resultCode: $0.0, reason: $0.1) }
        )
        let raisedDirectly: Set<PayabliErrorType> = [
            .deviceKeyUnavailable, .deviceSetupUnsupported, .deviceNotPending, .deviceSetupUnavailable,
            .deviceSetupNotConfigured, .deviceIdentityUnavailable, .tooManyOpenCharges, .chargeNotFinished
        ]
        let notProducedYet: Set<PayabliErrorType> = [
            .deviceServicesOutdated, // a Google Play cause, which this platform has no counterpart for
            .readerSessionExpired,
            .paymentNotHeld // no close call on this platform yet
        ]
        let produced = fromTheTable.union(fromActivation).union(raisedDirectly)
        for type in PayabliErrorType.allCases where (3001 ... 3999).contains(type.number) {
            XCTAssertTrue(
                produced.contains(type) != notProducedYet.contains(type),
                "\(type) is either produced and listed as not, or neither"
            )
        }
    }

    // MARK: - What passes through

    func testATapToPayErrorPassesThroughUnchanged() throws {
        let raised = TapToPayError(
            type: .deviceKeyUnavailable, reason: "r", detail: "d", paymentTransId: "TXN-9", capture: .unknown
        )
        let host = try translated(raised)
        XCTAssertEqual(host.type, raised.type)
        XCTAssertEqual(host.reason, raised.reason)
        XCTAssertEqual(host.detail, raised.detail)
        XCTAssertEqual(host.paymentTransId, raised.paymentTransId)
        XCTAssertEqual(host.capture, raised.capture)
    }

    func testCancellationStaysACancellation() {
        let host = TapToPayErrorTranslation.hostError(for: CancellationError())
        XCTAssertTrue(host is CancellationError, "got \(host)")
    }

    func testAnErrorTheSDKDoesNotKnowIsUnknown() throws {
        struct Unrecognised: Error {}
        let host = try translated(Unrecognised())
        XCTAssertEqual(host.type, .unknown)
        XCTAssertEqual(host.reason, PayabliErrorType.unknown.message)
        XCTAssertNil(host.detail)
    }

    // MARK: - Capture and payment

    func testAFailureStillNamesThePaymentAndWhatItTook() throws {
        let host = try translated(PayabliTTPError.updateFailed(reason: "x", paymentTransId: "TXN-9", capture: .charged))
        XCTAssertEqual(host.paymentTransId, "TXN-9")
        XCTAssertEqual(host.capture, .charged)
    }

    func testOnlyAFailureAfterTheTapCanHaveTakenMoney() {
        for error in Self.allSamples {
            switch error {
            case .nfcFailed, .outcomeUnknown, .updateFailed:
                XCTAssertEqual(error.capture, .unknown, "\(error) was raised once a card was asked for")
            case .notInitialized, .invalidState, .notReady, .devicePendingActivation, .attestationRevoked,
                 .attestationFailed, .deviceSetupRequired, .deviceSetupRefused, .entryPointRefused, .configFailed,
                 .cardPresentNotEnabled, .readerSetupFailed, .readerCredentialsUnusable, .readerHardwareUnsupported,
                 .readerUnavailable, .guardFailed, .readerDeviceRefused, .paymentNotOpened,
                 .tokenExpired, .activationFailed, .activationCodeMalformed, .networkError, .termsNotAccepted,
                 .readerOSVersionNotSupported, .cardDeclined, .paymentNotTaken:
                XCTAssertEqual(error.capture, .notCharged, "\(error) took no money")
            }
        }
    }

    func testAReaderThatWasNeverAskedForACardChargedNothingWhateverPaymentItNames() {
        let err = PayabliTTPError.readerSetupFailed(reason: "Reader not prepared", paymentTransId: "TXN-9")
        XCTAssertEqual(err.capture, .notCharged)
        XCTAssertEqual(err.paymentTransId, "TXN-9")
    }

    func testAnUnsupportedOSAnswersTheCaptureItWasRaisedWith() {
        XCTAssertEqual(PayabliTTPError.readerOSVersionNotSupported().capture, .notCharged)
        let duringARead = PayabliTTPError.readerOSVersionNotSupported(paymentTransId: "TXN-9", capture: .unknown)
        XCTAssertEqual(duringARead.capture, .unknown)
        XCTAssertEqual(duringARead.paymentTransId, "TXN-9")
    }

    func testAFailedReadForAnOpenedPaymentMayHaveBeenCharged() {
        let err = PayabliTTPError.nfcFailed(reason: "x", paymentTransId: "TXN-9")
        XCTAssertEqual(err.capture, .unknown)
        XCTAssertEqual(err.paymentTransId, "TXN-9")
    }

    func testAFailureBeforeAPaymentWasOpenedNamesNone() {
        XCTAssertNil(PayabliTTPError.paymentNotOpened(reason: "x").paymentTransId)
    }

    // MARK: - The NSError an Objective-C caller receives

    func testAnObjectiveCCallerReceivesTheCatalogNumberCaptureAndPayment() throws {
        let host = try translated(PayabliTTPError.cardDeclined(paymentTransId: "TXN-9"))
        let nsError = host.toPayabliNSError()
        XCTAssertEqual(nsError.domain, "com.payabli.ttp")
        XCTAssertEqual(nsError.code, PayabliErrorType.cardDeclined.number)
        XCTAssertEqual(nsError.userInfo["PayabliErrorType"] as? String, PayabliErrorType.cardDeclined.rawValue)
        XCTAssertEqual(nsError.userInfo["capture"] as? Int, PayabliTTPCapture.notCharged.rawValue)
        XCTAssertEqual(nsError.userInfo["paymentTransId"] as? String, "TXN-9")
    }

    func testAnObjectiveCCallerReceivesThePaymentNotTakenCodeCaptureAndPayment() throws {
        let host = try translated(PayabliTTPError.paymentNotTaken(paymentTransId: "TXN-9"))
        let nsError = host.toPayabliNSError()
        XCTAssertEqual(nsError.domain, "com.payabli.ttp")
        XCTAssertEqual(nsError.code, PayabliErrorType.paymentNotTaken.number)
        XCTAssertEqual(nsError.userInfo["PayabliErrorType"] as? String, PayabliErrorType.paymentNotTaken.rawValue)
        XCTAssertEqual(nsError.userInfo["capture"] as? Int, PayabliTTPCapture.notCharged.rawValue)
        XCTAssertEqual(nsError.userInfo["paymentTransId"] as? String, "TXN-9")
    }

    func testACancellationBridgesAsSwiftDoes() {
        let nsError = CancellationError().toPayabliNSError()
        XCTAssertNotEqual(nsError.domain, "com.payabli.ttp")
    }

    // MARK: - What the transaction client's own failures reach a host as

    /// A bare 404 from the opening is the paypoint's configuration, so it answers
    /// under the code that says so rather than an unknown one.
    func testABare404FromInitiateNamesThePaypointsConfiguration() async throws {
        try await assertInitiateAnswers(as: .cardPresentNotEnabled) { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!,
                Data()
            )
        }
    }

    /// A declined opening is the payment's own answer: the paypoint took no
    /// payment, and it says so under the code that names that.
    func testADeclinedInitiateNamesThePaymentsOwnCode() async throws {
        try await assertInitiateAnswers(as: .paymentNotOpened) { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"code":"D0001","reason":"not opened"}"#.utf8)
            )
        }
    }

    // MARK: - Fixtures

    private func translated(_ error: Error, file: StaticString = #filePath, line: UInt = #line) throws -> TapToPayError {
        let host = TapToPayErrorTranslation.hostError(for: error)
        return try XCTUnwrap(host as? TapToPayError, "got \(type(of: host))", file: file, line: line)
    }

    /// A transaction client on a stubbed network, the way the facade holds one.
    private func makeClient() throws -> TTPTransactionClient {
        let config = try PayabliConfig(entryPoint: "myEntry", environment: .sandbox, tokenProvider: { "seed" })
        let auth = PayabliAuth(config: config)
        let service = PayabliService(
            environment: .sandbox,
            readToken: { try await auth.currentAccessToken() },
            client: .none,
            session: StubURLProtocol.makeSession()
        )
        let transport = AuthenticatedTransport(
            base: service,
            auth: auth,
            logger: PayabliLogger(category: .network)
        )
        return TTPTransactionClient(transport: transport)
    }

    /// Drives one initiate against `handler` and reads the answer a host gets.
    private func assertInitiateAnswers(
        as type: PayabliErrorType,
        handler: @escaping StubURLProtocol.Handler,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        StubURLProtocol.handler = handler
        let client = try makeClient()
        do {
            _ = try await client.initiate(
                entryPoint: "myEntry",
                deviceId: "dev_1",
                idempotencyKey: "key-1",
                paymentDetails: PayabliTTPPaymentDetails(amount: 1, currency: "USD")
            )
            XCTFail("initiate succeeded", file: file, line: line)
        } catch {
            let host = TapToPayErrorTranslation.hostError(for: error)
            XCTAssertEqual((host as? TapToPayError)?.type, type, "\(error)", file: file, line: line)
        }
    }

    /// The published entry for each case, written out independently of the table under test. A new case
    /// stops this compiling until it is given one.
    private static func expectedType(of error: PayabliTTPError) -> PayabliErrorType {
        switch error {
        case .notInitialized: return .sessionNotInitialized
        case .invalidState: return .validation
        case .notReady: return .terminalNotReady
        case .devicePendingActivation: return .devicePendingActivation
        case .attestationRevoked: return .deviceSetupRequired
        case .deviceSetupRequired: return .deviceSetupRequired
        case .deviceSetupRefused: return .deviceSetupRefused
        case .entryPointRefused: return .entryPointRefused
        case .attestationFailed: return .unknown
        case .configFailed: return .unknown
        case .readerSetupFailed: return .unknown
        case .readerCredentialsUnusable: return .readerCredentialsUnusable
        case .cardPresentNotEnabled: return .cardPresentNotEnabled
        case .readerHardwareUnsupported: return .deviceHardwareUnsupported
        case .guardFailed: return .sdkInternalError
        case .nfcFailed: return .tapNotCompleted
        case .paymentNotOpened: return .paymentNotOpened
        case .updateFailed: return .paymentNotClosed
        case .tokenExpired: return .tokenExpired
        case .activationFailed: return .unknown
        case .activationCodeMalformed: return .activationCodeMalformed
        case .networkError: return .networkError
        case .termsNotAccepted: return .termsNotAccepted
        case .readerOSVersionNotSupported: return .deviceOSUnsupported
        case .readerUnavailable: return .readerUnavailable
        case .readerDeviceRefused: return .readerDeviceRefused
        case .cardDeclined: return .cardDeclined
        case .outcomeUnknown: return .paymentOutcomeUnknown
        case .paymentNotTaken: return .paymentNotTaken
        }
    }

    private static let allSamples: [PayabliTTPError] = [
        .notInitialized,
        .invalidState(current: .ready, attempted: "x"),
        .notReady(current: .idle),
        .devicePendingActivation,
        .attestationRevoked(reason: "x"),
        .attestationFailed(reason: "x"),
        .deviceSetupRequired(reason: "x"),
        .deviceSetupRefused(reason: "x"),
        .entryPointRefused(reason: "x"),
        .configFailed(reason: "x"),
        .cardPresentNotEnabled,
        .readerSetupFailed(reason: "x"),
        .readerCredentialsUnusable,
        .readerHardwareUnsupported,
        .readerUnavailable(reason: "x"),
        .guardFailed(reason: "x"),
        .readerDeviceRefused(reason: "x"),
        .nfcFailed(reason: "x"),
        .paymentNotOpened(reason: "x"),
        .updateFailed(reason: "x", paymentTransId: "TXN", capture: .unknown),
        .tokenExpired,
        .activationFailed(reason: "x"),
        .activationCodeMalformed,
        .networkError(reason: "x"),
        .termsNotAccepted,
        .readerOSVersionNotSupported(),
        .cardDeclined(paymentTransId: "TXN"),
        .outcomeUnknown(paymentTransId: "TXN"),
        .paymentNotTaken(paymentTransId: "TXN")
    ]
}
