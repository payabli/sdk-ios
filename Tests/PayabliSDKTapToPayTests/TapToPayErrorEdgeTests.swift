import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// Every public card-present call, in Swift and in Objective-C, hands its failure to a host as one
/// `TapToPayError` carrying the catalog entry for its cause.
@MainActor
final class TapToPayErrorEdgeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = Self.stubHandler
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - Swift

    func testEveryCallHandsAHostOneTypeCarryingItsClassification() async throws {
        let calls: [(String, (PayabliTTP) async throws -> Void)] = [
            ("initialize", { try await $0.initialize() }),
            ("reinitializeIfNeeded", { try await $0.reinitializeIfNeeded() }),
            ("charge", { _ = try await $0.charge(type: .sale, paymentDetails: Self.paymentDetails) }),
            ("areTermsAccepted", { _ = try await $0.areTermsAccepted() }),
            ("presentTerms", { try await $0.presentTerms() })
        ]
        for (name, call) in calls {
            let ttp = try makeTTP(failingWith: PayabliTTPError.readerSetupFailed(reason: "no reader"))
            do {
                try await call(ttp)
                XCTFail("\(name) succeeded")
            } catch let error as TapToPayError {
                XCTAssertEqual(error.type, .readerUnavailable, name)
                XCTAssertEqual(error.reason, PayabliErrorType.readerUnavailable.message, name)
                XCTAssertEqual(error.detail, "no reader", name)
            } catch {
                XCTFail("\(name) handed a host \(type(of: error))")
            }
        }
    }

    func testAnActivationOutOfOrderIsADeviceNotPending() async throws {
        let ttp = try makeTTP(failingWith: nil)
        do {
            try await ttp.activateDevice(activationCode: "123456")
            XCTFail("activateDevice succeeded")
        } catch let error as TapToPayError {
            XCTAssertEqual(error.type, .deviceNotPending)
        }
    }

    // MARK: - Objective-C

    func testEveryObjectiveCCompanionCompletesWithTheCatalogNumber() async throws {
        let calls: [(String, (PayabliTTP, @escaping (NSError?) -> Void) -> Void)] = [
            ("initialize", { ttp, done in ttp.initialize(completion: done) }),
            ("reinitializeIfNeeded", { ttp, done in ttp.reinitializeIfNeeded(completion: done) }),
            ("charge", { ttp, done in
                ttp.charge(
                    type: 0,
                    paymentDetails: PayabliTTPPaymentDetailsObjC(
                        amount: 1, serviceFee: 0, currency: "USD", paymentDescription: nil
                    ),
                    customer: nil,
                    invoice: nil,
                    orderDescription: nil
                ) { _, error in done(error) }
            }),
            ("areTermsAccepted", { ttp, done in ttp.areTermsAccepted { _, error in done(error) } }),
            ("presentTerms", { ttp, done in ttp.presentTerms(completion: done) })
        ]
        for (name, call) in calls {
            let ttp = try makeTTP(failingWith: PayabliTTPError.readerSetupFailed(reason: "no reader"))
            let completed = expectation(description: name)
            call(ttp) { error in
                XCTAssertEqual(error?.domain, "com.payabli.ttp", name)
                XCTAssertEqual(error?.code, PayabliErrorType.readerUnavailable.number, name)
                XCTAssertEqual(
                    error?.userInfo["PayabliErrorType"] as? String,
                    PayabliErrorType.readerUnavailable.rawValue,
                    name
                )
                completed.fulfill()
            }
            await fulfillment(of: [completed], timeout: 5)
        }
    }

    func testTheObjectiveCActivationCompletesWithTheCatalogNumber() async throws {
        let ttp = try makeTTP(failingWith: nil)
        let completed = expectation(description: "activateDevice")
        ttp.activateDevice(activationCode: "123456") { error in
            XCTAssertEqual(error?.domain, "com.payabli.ttp")
            XCTAssertEqual(error?.code, PayabliErrorType.deviceNotPending.number)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 5)
    }

    // MARK: - Fixtures

    private static let paymentDetails = PayabliTTPPaymentDetails(amount: 1)

    /// An enrolled device whose reader refuses every request with `failure`.
    private func makeTTP(failingWith failure: PayabliTTPError?) throws -> PayabliTTP {
        let provider = MockTapToPayProvider()
        if let failure {
            provider.prepareReaderResult = .failure(failure)
            provider.areTermsAcceptedResult = .failure(failure)
            provider.presentTermsResult = .failure(failure)
        }
        let attestation = MockDeviceAttestationService()
        attestation.isAlreadyAttested = true
        let config = try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" })
        return PayabliTTP(
            config: config,
            provider: provider,
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
    }

    /// A configuration envelope for any request, so a call reaches the reader without caring about the wire.
    private static let stubHandler: StubURLProtocol.Handler = { request in
        let body: [String: Any] = [
            "responseCode": 1,
            "isSuccess": true,
            "responseData": [
                "credentials": ["secretKey": "s", "apiKey": "a", "merchantId": "m", "terminalId": "t"]
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
}
