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

    func testAddBankAccountRejectsInvalidHolderType() async throws {
        let component = try await makeBridge(
            tokenHandler: { completion in
                completion("token", nil)
            }
        )
        let expectation = expectation(description: "completion called")

        component.addBankAccount(
            accountNumber: "123456789",
            accountType: "Checking",
            holderName: "Jane Doe",
            routingNumber: "021000021",
            secCode: "WEB",
            holderType: "company",
            achValidation: true,
            createAnonymous: false,
            forceCustomerCreation: true,
            temporary: false,
            source: "objc-test"
        ) { method, error in
            XCTAssertNil(method)
            XCTAssertEqual(error?.domain, "com.payabli.payIn")
            XCTAssertEqual(error?.code, -2)
            XCTAssertEqual(error?.localizedDescription, "holderType must be personal or business")
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1)
    }

    func testStoredPaymentMethodWrapperConvertsValuesAndResponse() {
        let storedMethod = PayabliPayInStoredPaymentMethod(
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

        let wrapper = PayabliPayInStoredPaymentMethodObjC(storedMethod)

        XCTAssertEqual(wrapper.storedMethodId, "stored-123")
        XCTAssertEqual(wrapper.method, "bankAccount")
        XCTAssertEqual(wrapper.methodReferenceId, "method-123")
        XCTAssertEqual(wrapper.resultCode, 1)
        XCTAssertEqual(wrapper.customerId, 4440)
        XCTAssertEqual(wrapper.responseText, "Success")
        XCTAssertEqual(wrapper.apiResponse["responseText"] as? String, "Success")
    }

    func testAddBankAccountRejectsInvalidArgumentsSynchronously() async throws {
        let component = try await makeBridge(
            tokenHandler: { completion in completion("unused", nil) }
        )

        var invalidAccountTypeError: NSError?
        component.addBankAccount(
            accountNumber: "111111111",
            accountType: "Business",
            holderName: "Jane Doe",
            routingNumber: "123456780",
            secCode: nil,
            holderType: nil,
            achValidation: false,
            createAnonymous: false,
            forceCustomerCreation: false,
            temporary: false,
            source: nil
        ) { result, error in
            XCTAssertNil(result)
            invalidAccountTypeError = error
        }

        var invalidSecCodeError: NSError?
        component.addBankAccount(
            accountNumber: "111111111",
            accountType: PayabliPayInAccountType.checking.rawValue,
            holderName: "Jane Doe",
            routingNumber: "123456780",
            secCode: "POP",
            holderType: nil,
            achValidation: false,
            createAnonymous: false,
            forceCustomerCreation: false,
            temporary: false,
            source: nil
        ) { result, error in
            XCTAssertNil(result)
            invalidSecCodeError = error
        }

        XCTAssertEqual(invalidAccountTypeError?.code, -2)
        XCTAssertEqual(
            invalidAccountTypeError?.localizedDescription,
            "accountType must be Checking or Savings"
        )
        XCTAssertEqual(invalidSecCodeError?.code, -2)
        XCTAssertEqual(invalidSecCodeError?.localizedDescription, "secCode must be PPD, WEB, TEL, CCD, or BOC")
    }

    func testAddCardReturnsValidationErrorWithoutCallingTokenHandler() async throws {
        let completionExpectation = expectation(description: "ObjC card completion")
        let component = try await makeBridge(
            tokenHandler: { _ in XCTFail("Token handler should not be called before local validation fails") }
        )

        component.addCard(
            cardNumber: "4111111111111111",
            expiry: "02/28",
            holderName: "",
            securityCode: "123",
            postalCode: "33139",
            createAnonymous: false,
            forceCustomerCreation: false,
            temporary: false,
            source: nil
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

        component.addCard(
            cardNumber: "4111111111111111",
            expiry: "02/28",
            holderName: "Jane Doe",
            securityCode: "123",
            postalCode: "33139",
            createAnonymous: false,
            forceCustomerCreation: false,
            temporary: false,
            source: nil
        ) { result, error in
            XCTAssertNil(result)
            // The session's holder owns the provider, so the host's own NSError is wrapped in this
            // SDK's `.tokenProviderFailed` and reaches the bridge as a PayabliError rather than
            // verbatim.
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

        component.addPaymentMethod(
            .card(PayabliPayInCardData(
                cardNumber: cardNumber,
                expiry: "02/28",
                holderName: "Jane Doe",
                securityCode: securityCode,
                postalCode: "33139"
            )),
            options: PayabliPayInOptions()
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

        component.addPaymentMethod(
            .bankAccount(PayabliPayInBankAccountData(
                accountNumber: accountNumber,
                accountType: .checking,
                holderName: "Jane Doe",
                routingNumber: "123456780"
            )),
            options: PayabliPayInOptions()
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

        component.addBankAccount(
            accountNumber: "1111111111",
            accountType: PayabliPayInAccountType.checking.rawValue,
            holderName: "Jane Doe",
            routingNumber: "123456780",
            secCode: nil,
            holderType: PayabliPayInAccountHolderType.personal.rawValue,
            achValidation: true,
            createAnonymous: false,
            forceCustomerCreation: false,
            temporary: false,
            source: nil
        ) { result, error in
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
