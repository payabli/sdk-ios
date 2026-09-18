import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow
import XCTest

@MainActor
final class PaymentMethodObjCBridgeTests: XCTestCase {
    func testAddACHRejectsInvalidHolderType() throws {
        let component = try PayabliPayInPaymentFlowObjC(
            tokenHandler: { completion in
                completion("token", nil)
            },
            entryPoint: "entry",
            environment: .sandbox
        )
        let expectation = expectation(description: "completion called")

        component.addACH(
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
            XCTAssertEqual(error?.domain, "com.payabli.payInPaymentFlow")
            XCTAssertEqual(error?.code, -2)
            XCTAssertEqual(error?.localizedDescription, "holderType must be personal or business")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testStoredPaymentMethodWrapperConvertsValuesAndResponse() {
        let storedMethod = PayabliPayInPaymentFlowStoredPaymentMethod(
            storedMethodId: "stored-123",
            methodReferenceId: "method-123",
            resultCode: 1,
            resultText: "Approved",
            customerId: 4440,
            responseText: "Success",
            apiResponse: PayabliPayInPaymentFlowTokenStorageAPIResponse(
                isSuccess: true,
                responseText: "Success",
                responseCode: 200,
                responseData: PayabliPayInPaymentFlowTokenStorageAPIResponseData(
                    referenceId: "stored-123",
                    resultCode: 1,
                    resultText: "Approved",
                    customerId: 4440,
                    methodReferenceId: "method-123"
                )
            )
        )

        let wrapper = PayabliPayInPaymentFlowStoredPaymentMethodObjC(storedMethod)

        XCTAssertEqual(wrapper.storedMethodId, "stored-123")
        XCTAssertEqual(wrapper.methodReferenceId, "method-123")
        XCTAssertEqual(wrapper.resultCode, 1)
        XCTAssertEqual(wrapper.customerId, 4440)
        XCTAssertEqual(wrapper.responseText, "Success")
        XCTAssertEqual(wrapper.apiResponse["responseText"] as? String, "Success")
    }

    func testAddACHRejectsInvalidArgumentsSynchronously() throws {
        let component = try PayabliPayInPaymentFlowObjC(
            tokenHandler: { completion in completion("unused", nil) },
            entryPoint: "entry",
            environment: .sandbox
        )

        var invalidAccountTypeError: NSError?
        component.addACH(
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
        component.addACH(
            accountNumber: "111111111",
            accountType: PayabliPayInPaymentFlowACHAccountType.checking.rawValue,
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
        let component = try PayabliPayInPaymentFlowObjC(
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

        await fulfillment(of: [completionExpectation], timeout: 1)
    }

    func testAccessTokenHandlerErrorIsReturnedAndDoubleCallbacksAreIgnored() async throws {
        let completionExpectation = expectation(description: "ObjC token error completion")
        let tokenError = NSError(
            domain: "TokenProvider",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Token unavailable"]
        )
        let component = try PayabliPayInPaymentFlowObjC(
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
            XCTAssertEqual(error?.domain, "com.payabli.payInPaymentFlow")
            XCTAssertEqual(error?.code, -3)
            XCTAssertEqual(
                error?.userInfo["PayabliErrorCode"] as? String,
                PayabliErrorCode.tokenProviderFailed.rawValue
            )
            completionExpectation.fulfill()
        }

        await fulfillment(of: [completionExpectation], timeout: 1)
    }

    /// The deadline this closure exists for: a `tokenHandler` that retains its completion instead of
    /// calling it, the "forgotten completion" case a callback-shaped API invites. `PayabliAuth`
    /// cancels the provider call at its 30s bound; this proves the ObjC bridge's
    /// `withTaskCancellationHandler` turns that into a resumed continuation instead of one left
    /// parked, and that the host's completion finally arriving after does not resume it twice.
    ///
    /// Runs the real 30s bound rather than a shortened one: nothing built for this bridge lets a
    /// test substitute the clock without adding a new initializer to reach it, and the token step
    /// fails before any network call, so the wait costs time and nothing else.
    func testTokenHandlerThatNeverCompletesIsRefusedAtTheDeadlineAndALateCallbackIsIgnored() async throws {
        let completionExpectation = expectation(description: "ObjC token deadline completion")
        var lateCompletion: ((String?, NSError?) -> Void)?
        let component = try PayabliPayInPaymentFlowObjC(
            tokenHandler: { completion in
                lateCompletion = completion
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
            XCTAssertEqual(error?.domain, "com.payabli.payInPaymentFlow")
            XCTAssertEqual(error?.code, -3)
            XCTAssertEqual(
                error?.userInfo["PayabliErrorCode"] as? String,
                PayabliErrorCode.tokenProviderFailed.rawValue
            )
            completionExpectation.fulfill()
        }

        await fulfillment(of: [completionExpectation], timeout: 35)

        // A crash here (a double resume of the same continuation) is the failure mode this guards:
        // XCTest reporting green on this call proves the guard, not just this assertion.
        lateCompletion?("late-token", nil)
    }

    func testNilTokenAndNilErrorProducesInvalidTokenProviderError() async throws {
        let completionExpectation = expectation(description: "ObjC nil token completion")
        let component = try PayabliPayInPaymentFlowObjC(
            tokenHandler: { completion in completion(nil, nil) },
            entryPoint: "entry",
            environment: .sandbox
        )

        component.addACH(
            accountNumber: "1111111111",
            accountType: PayabliPayInPaymentFlowACHAccountType.checking.rawValue,
            holderName: "Jane Doe",
            routingNumber: "123456780",
            secCode: nil,
            holderType: PayabliPayInPaymentFlowACHHolderType.personal.rawValue,
            achValidation: true,
            createAnonymous: false,
            forceCustomerCreation: false,
            temporary: false,
            source: nil
        ) { result, error in
            XCTAssertNil(result)
            XCTAssertEqual(error?.domain, "com.payabli.payInPaymentFlow")
            XCTAssertEqual(error?.code, -3)
            completionExpectation.fulfill()
        }

        await fulfillment(of: [completionExpectation], timeout: 1)
    }
}
