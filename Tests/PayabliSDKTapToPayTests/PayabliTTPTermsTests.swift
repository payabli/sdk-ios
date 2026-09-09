import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

@MainActor
final class PayabliTTPTermsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = Self.stubHandler
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    /// Returns a config envelope for any request, so a test reaches the reader
    /// phase without caring about the wire.
    private static let stubHandler: StubURLProtocol.Handler = { request in
        let body: [String: Any] = [
            "responseCode": 1,
            "isSuccess": true,
            "responseData": [
                "credentials": [
                    "secretKey": "s",
                    "apiKey": "a",
                    "merchantId": "m",
                    "terminalId": "t"
                ]
            ],
            "paymentToken": "payment_tok"
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        return (HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!, data)
    }

    private func makeTTP(
        provider: MockTapToPayProvider = MockTapToPayProvider(),
        attestation: MockDeviceAttestationService = MockDeviceAttestationService()
    ) throws -> (PayabliTTP, MockTapToPayProvider) {
        let config = try PayabliConfig(
            accessToken: "seed_token",
            entryPoint: "e",
            environment: .sandbox
        )
        let ttp = PayabliTTP(
            config: config,
            appId: "appid",
            provider: provider,
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        return (ttp, provider)
    }

    // MARK: - The facade forwards, and adds nothing

    func testReportsAcceptedWhenTheProviderDoes() async throws {
        let (ttp, provider) = try makeTTP()
        provider.areTermsAcceptedResult = .success(true)

        let accepted = try await ttp.areTermsAccepted()

        XCTAssertTrue(accepted)
        XCTAssertEqual(provider.areTermsAcceptedCalls, 1)
    }

    func testReportsNotAcceptedWhenTheProviderDoes() async throws {
        let (ttp, provider) = try makeTTP()
        provider.areTermsAcceptedResult = .success(false)

        let accepted = try await ttp.areTermsAccepted()

        XCTAssertFalse(accepted)
    }

    /// A reader that cannot answer is a different outcome from one answering
    /// "not accepted", and a host showing a terms screen has to tell them apart.
    func testAReaderThatCannotAnswerThrowsRatherThanReportingNotAccepted() async throws {
        let (ttp, provider) = try makeTTP()
        provider.areTermsAcceptedResult = .failure(
            PayabliTTPError.readerSetupFailed(reason: "Reader not prepared")
        )

        do {
            _ = try await ttp.areTermsAccepted()
            XCTFail("expected the provider's failure to surface")
        } catch let error as PayabliTTPError {
            guard case .readerSetupFailed = error else {
                return XCTFail("expected readerSetupFailed, got \(error)")
            }
        }
    }

    /// The question is asked on every call. Acceptance is granted and withdrawn
    /// outside this process, so an answer the SDK remembered would go stale with
    /// nothing failing.
    func testAsksThePlatformEveryTimeRatherThanCaching() async throws {
        let (ttp, provider) = try makeTTP()
        provider.areTermsAcceptedResult = .success(false)
        _ = try await ttp.areTermsAccepted()

        provider.areTermsAcceptedResult = .success(true)
        let second = try await ttp.areTermsAccepted()

        XCTAssertTrue(second)
        XCTAssertEqual(provider.areTermsAcceptedCalls, 2)
    }

    // MARK: - The guarantee the feature rests on

    /// The facade puts no state guard in front of the question, and this is what
    /// holds it there. A provider that reports unaccepted terms leaves the session
    /// outside `.ready`, which is the one moment a host needs the answer; a guard
    /// on `sessionState == .ready` would refuse exactly then.
    ///
    /// Driven through the mock because the shipped provider reaches this only on
    /// a device: preparation cannot get past the session-token call without reader
    /// hardware, so the branch that reports unaccepted terms is unreachable here.
    func testTheQuestionIsAnswerableWhenTheSessionIsNotReady() async throws {
        let (ttp, provider) = try makeTTP()
        provider.prepareReaderResult = .failure(PayabliTTPError.termsNotAccepted)
        provider.areTermsAcceptedResult = .success(false)

        do {
            try await ttp.initialize()
            XCTFail("expected initialize to report unaccepted terms")
        } catch let error as PayabliTTPError {
            guard case .termsNotAccepted = error else {
                return XCTFail("expected termsNotAccepted, got \(error)")
            }
        }

        XCTAssertNotEqual(ttp.sessionState, .ready)
        let accepted = try await ttp.areTermsAccepted()
        XCTAssertFalse(accepted)
    }

    // MARK: - ObjC companion

    func testObjCCompanionDeliversTheAnswer() async throws {
        let (ttp, provider) = try makeTTP()
        provider.areTermsAcceptedResult = .success(true)

        let done = expectation(description: "completion")
        ttp.areTermsAccepted { accepted, error in
            XCTAssertTrue(accepted)
            XCTAssertNil(error)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 1)
    }

    /// `false` on the failure path is the bridging default, not an answer. An ObjC
    /// caller reading the flag without the error would treat a broken reader as an
    /// unaccepted merchant.
    func testObjCCompanionReportsFailureAsAnErrorAndNotAsNotAccepted() async throws {
        let (ttp, provider) = try makeTTP()
        provider.areTermsAcceptedResult = .failure(PayabliTTPError.termsNotAccepted)

        let done = expectation(description: "completion")
        ttp.areTermsAccepted { accepted, error in
            XCTAssertFalse(accepted)
            XCTAssertEqual(error?.domain, "com.payabli.ttp")
            XCTAssertEqual(error?.code, 14)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 1)
    }
}
