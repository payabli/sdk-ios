@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// A bridge completion arrives through a main-actor task, which a runner busy with the rest of the suite can
/// hold for longer than a second.
private let mainActorCompletionTimeout: TimeInterval = 10

@MainActor
final class PaymentMethodObjCBridgeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // A refusal reports at once, and a report would otherwise ask the host's token handler and reach the network.
        PayabliSession.resetForTesting(telemetryTransport: DiscardingTelemetryTransport())
    }

    override func tearDown() {
        PayabliSession.resetForTesting()
        super.tearDown()
    }

    private func makeBridge(
        tokenHandler: @escaping (@escaping (String?, NSError?) -> Void) -> Void
    ) async throws -> PayabliPayInObjC {
        try await PayabliSessionObjC.initialize(
            tokenHandler: tokenHandler,
            entryPoint: "entry",
            environment: .sandbox
        )
        return try PayabliPayInObjC.create()
    }

    func testEachStoreFlagReachesItsOwnOption() throws {
        let flags: [(ReferenceWritableKeyPath<PayabliPayInStoreRequestObjC, NSNumber?>, KeyPath<PayabliPayInStoreOptions, Bool?>)] = [
            (\.achValidation, \.achValidation),
            (\.createAnonymous, \.createAnonymous),
            (\.forceCustomerCreation, \.forceCustomerCreation),
            (\.temporary, \.temporary)
        ]

        for (set, _) in flags {
            let request = try storeRequest()
            request[keyPath: set] = true
            let options = request.toSwift().options
            for (other, read) in flags {
                XCTAssertEqual(options[keyPath: read], other == set ? true : nil, "\(set) set \(read)")
            }
        }
    }

    func testAStoreRequestCarriesItsSourceAndLeavesUnsetFlagsUnsent() throws {
        let request = try storeRequest()
        request.source = "objc-source"

        let options = request.toSwift().options

        XCTAssertEqual(options.source, "objc-source")
        XCTAssertNil(options.achValidation)
        XCTAssertNil(options.createAnonymous)
        XCTAssertNil(options.forceCustomerCreation)
        XCTAssertNil(options.temporary)
    }

    private func storeRequest() throws -> PayabliPayInStoreRequestObjC {
        try XCTUnwrap(PayabliPayInStoreRequestObjC.bankAccount(
            accountNumber: "123456789",
            routingNumber: "021000021",
            accountType: .checking,
            holderName: "Jane Doe",
            holderType: .unspecified,
            secCode: .unspecified,
            deviceId: nil
        ))
    }

    func testStoredMethodWrapperConvertsValuesAndResponse() {
        let storedMethod = PayabliPayInStoredMethod(
            storedMethodId: "stored-123",
            method: .bankAccount,
            methodReferenceId: "method-123",
            resultCode: 1,
            resultText: "Approved",
            customerId: 4440,
            responseText: "Success",
            apiResponse: PayabliPayInTokenStorageAPIResponse(
                isSuccess: true,
                responseText: "Success",
                responseCode: 200,
                responseData: PayabliPayInTokenStorageAPIResponseData(
                    referenceId: "stored-123",
                    resultCode: 1,
                    resultText: "Approved",
                    customerId: 4440,
                    methodReferenceId: "method-123"
                )
            )
        )

        let wrapper = PayabliPayInStoredMethodObjC(storedMethod)

        XCTAssertEqual(wrapper.storedMethodId, "stored-123")
        XCTAssertEqual(wrapper.method, "bankAccount")
        XCTAssertEqual(wrapper.methodReferenceId, "method-123")
        XCTAssertEqual(wrapper.resultCode, 1)
        XCTAssertEqual(wrapper.customerId, 4440)
        XCTAssertEqual(wrapper.responseText, "Success")
        XCTAssertEqual(wrapper.apiResponse["responseText"] as? String, "Success")
    }

    func testStoreMethodReturnsValidationErrorWithoutCallingTokenHandler() async throws {
        let completionExpectation = expectation(description: "ObjC card completion")
        let component = try await makeBridge(
            tokenHandler: { _ in XCTFail("Token handler should not be called before local validation fails") }
        )

        component.storeMethod(
            PayabliPayInStoreRequestObjC.card(
                cardNumber: "4111111111111111",
                expiryMonth: 2,
                expiryYear: 2028,
                securityCode: "123",
                holderName: "",
                postalCode: "33139"
            )
        ) { result, error in
            XCTAssertNil(result)
            XCTAssertEqual(error?.code, PayabliErrorType.validation.number)
            XCTAssertEqual(error?.userInfo["PayabliErrorType"] as? String, PayabliErrorType.validation.rawValue)
            XCTAssertEqual(error?.localizedDescription, "Cardholder name is required.")
            completionExpectation.fulfill()
        }

        await fulfillment(of: [completionExpectation], timeout: mainActorCompletionTimeout)
    }

    func testAccessTokenHandlerErrorIsReturnedAndDoubleCallbacksAreIgnored() async throws {
        let completionExpectation = expectation(description: "ObjC token error completion")
        let tokenError = NSError(
            domain: "TokenProvider",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Token unavailable"]
        )
        let component = try await makeBridge(
            tokenHandler: { completion in
                completion(nil, tokenError)
                completion("late-token", nil)
            }
        )

        component.storeMethod(
            PayabliPayInStoreRequestObjC.card(
                cardNumber: "4111111111111111",
                expiryMonth: 2,
                expiryYear: 2028,
                securityCode: "123",
                holderName: "Jane Doe",
                postalCode: "33139"
            )
        ) { result, error in
            XCTAssertNil(result)
            XCTAssertEqual(error?.domain, "com.payabli.payIn")
            XCTAssertEqual(error?.code, PayabliErrorType.tokenProviderFailed.number)
            XCTAssertEqual(
                error?.userInfo["PayabliErrorType"] as? String,
                PayabliErrorType.tokenProviderFailed.rawValue
            )
            completionExpectation.fulfill()
        }

        await fulfillment(of: [completionExpectation], timeout: mainActorCompletionTimeout)
    }

    /// The buffers this facade builds from strings are the SDK's own: no host can reach them, so the
    /// task that spends them overwrites them at its end, on a stored method and a refusal alike.
    func testTheTaskClosesTheCardBuffersTheFacadeBuilt() async throws {
        let component = try await makeBridge(
            tokenHandler: { completion in completion(nil, nil) }
        )
        let cardNumber = SensitiveDigits.ofString("4111111111111111")
        let securityCode = SensitiveDigits.ofString("123")
        let completionExpectation = expectation(description: "closed card buffers completion")

        component.storeMethod(
            PayabliPayInStoreRequest(
                instrument: .card(PayabliPayInCardData(
                    cardNumber: cardNumber,
                    expiryMonth: 2,
                    expiryYear: 2028,
                    securityCode: securityCode,
                    holderName: "Jane Doe",
                    postalCode: "33139"
                )),
                options: PayabliPayInStoreOptions()
            )
        ) { method, error in
            XCTAssertNil(method)
            XCTAssertNotNil(error)
            completionExpectation.fulfill()
        }

        await fulfillment(of: [completionExpectation], timeout: mainActorCompletionTimeout)
        XCTAssertTrue(cardNumber.isWiped, "the task closed the card number buffer")
        XCTAssertTrue(securityCode.isWiped, "the task closed the security code buffer")
        XCTAssertEqual(
            cardNumber.rawCopy(), Array(repeating: 0, count: 16),
            "the card number is overwritten, not just released"
        )
        XCTAssertEqual(
            securityCode.rawCopy(), Array(repeating: 0, count: 3),
            "the security code is overwritten, not just released"
        )
    }

    func testTheTaskClosesTheAccountNumberTheFacadeBuilt() async throws {
        let component = try await makeBridge(
            tokenHandler: { completion in completion(nil, nil) }
        )
        let accountNumber = SensitiveDigits.ofString("1111111111")
        let completionExpectation = expectation(description: "closed account number completion")

        component.storeMethod(
            PayabliPayInStoreRequest(
                instrument: .bankAccount(PayabliPayInBankAccountData(
                    accountNumber: accountNumber,
                    routingNumber: "123456780",
                    accountType: .checking,
                    holderName: "Jane Doe"
                )),
                options: PayabliPayInStoreOptions()
            )
        ) { method, error in
            XCTAssertNil(method)
            XCTAssertNotNil(error)
            completionExpectation.fulfill()
        }

        await fulfillment(of: [completionExpectation], timeout: mainActorCompletionTimeout)
        XCTAssertTrue(accountNumber.isWiped, "the task closed the account number buffer")
        XCTAssertEqual(
            accountNumber.rawCopy(), Array(repeating: 0, count: 10),
            "the account number is overwritten, not just released"
        )
    }

    // Cancellation coverage for the bridge's token provider lives in
    // `PayabliSDKCoreTests/BridgedTokenProviderTests.swift` now, against the shared
    // `bridgedTokenProvider` both this facade and TapToPay's call.

    func testNilTokenAndNilErrorProducesInvalidTokenProviderError() async throws {
        let completionExpectation = expectation(description: "ObjC nil token completion")
        let component = try await makeBridge(
            tokenHandler: { completion in completion(nil, nil) }
        )
        let request = try XCTUnwrap(
            PayabliPayInStoreRequestObjC.bankAccount(
                accountNumber: "1111111111",
                routingNumber: "123456780",
                accountType: .checking,
                holderName: "Jane Doe",
                holderType: .personal,
                secCode: .unspecified,
                deviceId: nil
            ),
            "a bank account request whose named values are all real is a request"
        )

        component.storeMethod(request) { result, error in
            XCTAssertNil(result)
            XCTAssertEqual(error?.domain, "com.payabli.payIn")
            let type = (error?.userInfo["PayabliErrorType"] as? String).flatMap(PayabliErrorType.init(rawValue:))
            XCTAssertNotNil(type)
            XCTAssertEqual(error?.code, type?.number)
            completionExpectation.fulfill()
        }

        await fulfillment(of: [completionExpectation], timeout: mainActorCompletionTimeout)
    }
}
