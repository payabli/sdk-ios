import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow
import XCTest

@MainActor
final class PaymentMethodObjCBridgeTests: XCTestCase {
    func testAddACHRejectsInvalidHolderType() {
        let component = PayabliPayInPaymentFlowObjC(
            accessTokenHandler: { completion in
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
}
