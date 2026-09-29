import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// A bridge completion arrives through a main-actor task, which a runner busy with the rest of the suite can
/// hold for longer than a second.
private let mainActorCompletionTimeout: TimeInterval = 10

@MainActor
final class PaymentMethodObjCBridgeTests: XCTestCase {
    func testAddBankAccountRejectsInvalidHolderType() throws {
        let component = try PayabliPayInObjC(
            tokenHandler: { completion in
                completion("token", nil)
            },
            entryPoint: "entry",
            environment: .sandbox
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

        wait(for: [expectation], timeout: 1)
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

    func testAddBankAccountRejectsInvalidArgumentsSynchronously() throws {
        let component = try PayabliPayInObjC(
            tokenHandler: { completion in completion("unused", nil) },
            entryPoint: "entry",
            environment: .sandbox
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
        let component = try PayabliPayInObjC(
            tokenHandler: { _ in XCTFail("Token handler should not be called before local validation fails") },
            entryPoint: "entry",
            environment: .sandbox
        )

        component.addCard(
            cardNumber: "4111111111111111",
            expiration: "02/28",
            cardholderName: "",
            cvv: "123",
            billingZip: "33139",
            createAnonymous: false,
            forceCustomerCreation: false,
            temporary: false,
            source: nil
        ) { result, error in
            XCTAssertNil(result)
            XCTAssertEqual(error?.code, -3)
            XCTAssertEqual(error?.userInfo["PayabliErrorCode"] as? String, PayabliErrorCode.validation.rawValue)
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
        let component = try PayabliPayInObjC(
            tokenHandler: { completion in
                completion(nil, tokenError)
                completion("late-token", nil)
            },
            entryPoint: "entry",
            environment: .sandbox
        )

        component.addCard(
            cardNumber: "4111111111111111",
            expiration: "02/28",
            cardholderName: "Jane Doe",
            cvv: "123",
            billingZip: "33139",
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
            XCTAssertEqual(error?.code, -3)
            XCTAssertEqual(
                error?.userInfo["PayabliErrorCode"] as? String,
                PayabliErrorCode.tokenProviderFailed.rawValue
            )
            completionExpectation.fulfill()
        }

        await fulfillment(of: [completionExpectation], timeout: mainActorCompletionTimeout)
    }

    // Cancellation coverage for the bridge's token provider lives in
    // `PayabliSDKCoreTests/BridgedTokenProviderTests.swift` now, against the shared
    // `bridgedTokenProvider` both this facade and TapToPay's call.

    func testNilTokenAndNilErrorProducesInvalidTokenProviderError() async throws {
        let completionExpectation = expectation(description: "ObjC nil token completion")
        let component = try PayabliPayInObjC(
            tokenHandler: { completion in completion(nil, nil) },
            entryPoint: "entry",
            environment: .sandbox
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
            XCTAssertEqual(error?.code, -3)
            completionExpectation.fulfill()
        }

        await fulfillment(of: [completionExpectation], timeout: mainActorCompletionTimeout)
    }
}
