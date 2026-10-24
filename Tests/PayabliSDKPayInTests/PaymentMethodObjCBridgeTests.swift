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

    func testTheBankAccountFactoryRejectsAnInvalidHolderType() {
        XCTAssertNil(
            PayabliPayInStoreRequestObjC.bankAccount(
                accountNumber: "123456789",
                accountType: "Checking",
                holderName: "Jane Doe",
                routingNumber: "021000021",
                secCode: "WEB",
                holderType: "company"
            ),
            "a holder type that names none of the kinds is refused before a request exists"
        )
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

    func testTheBankAccountFactoryRejectsInvalidArguments() {
        XCTAssertNil(
            PayabliPayInStoreRequestObjC.bankAccount(
                accountNumber: "111111111",
                accountType: "Business",
                holderName: "Jane Doe",
                routingNumber: "123456780",
                secCode: nil,
                holderType: nil
            ),
            "an account type that names none of the kinds is refused before a request exists"
        )
        XCTAssertNil(
            PayabliPayInStoreRequestObjC.bankAccount(
                accountNumber: "111111111",
                accountType: PayabliPayInAccountType.checking.rawValue,
                holderName: "Jane Doe",
                routingNumber: "123456780",
                secCode: "POP",
                holderType: nil
            ),
            "an SEC code that names none of the kinds is refused before a request exists"
        )
    }

    func testStoreMethodReturnsValidationErrorWithoutCallingTokenHandler() async throws {
        let completionExpectation = expectation(description: "ObjC card completion")
        let component = try await makeBridge(
            tokenHandler: { _ in XCTFail("Token handler should not be called before local validation fails") }
        )

        component.storeMethod(
            PayabliPayInStoreRequestObjC.card(
                cardNumber: "4111111111111111",
                expiration: "02/28",
                cardholderName: "",
                cvv: "123",
                billingZip: "33139"
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
                expiration: "02/28",
                cardholderName: "Jane Doe",
                cvv: "123",
                billingZip: "33139"
            )
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
                accountType: PayabliPayInAccountType.checking.rawValue,
                holderName: "Jane Doe",
                routingNumber: "123456780",
                secCode: nil,
                holderType: PayabliPayInAccountHolderType.personal.rawValue
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
