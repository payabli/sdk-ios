import Foundation
import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

final class PayabliPayInFailureMessageTests: XCTestCase {
    func testEachCategoryDrawsItsMessageForAPaymentOrAnAuthorization() {
        for operation in [PayabliPayInOperation.capture, .authorize] {
            for category in PayabliErrorCategory.allCases {
                let expected = switch category {
                case .declined: "The payment was declined. Try another payment method."
                case .retryLater: "The payment couldn't be completed. Please try again."
                case .outcomeUnknown: "This payment may have gone through. Check before paying again."
                default: "The payment couldn't be completed."
                }
                XCTAssertEqual(
                    PayabliPayInFailureMessage.text(for: category, operation: operation),
                    expected,
                    "\(operation) \(category)"
                )
            }
        }
    }

    func testEachCategoryDrawsItsMessageForASave() {
        for category in PayabliErrorCategory.allCases {
            let expected = switch category {
            case .declined: "This payment method couldn't be saved. Try another one."
            case .retryLater: "The payment method couldn't be saved. Please try again."
            default: "The payment method couldn't be saved."
            }
            XCTAssertEqual(
                PayabliPayInFailureMessage.text(for: category, operation: .storePaymentMethod),
                expected,
                "\(category)"
            )
        }
    }

    func testAnErrorOutsideTheCatalogDrawsTheDefaultMessage() {
        XCTAssertEqual(
            PayabliPayInFailureMessage.text(for: URLError(.notConnectedToInternet), operation: .capture),
            "The payment couldn't be completed."
        )
        XCTAssertEqual(
            PayabliPayInFailureMessage.text(for: URLError(.notConnectedToInternet), operation: .storePaymentMethod),
            "The payment method couldn't be saved."
        )
    }

    func testACatalogErrorDrawsItsCategorysMessage() {
        XCTAssertEqual(
            PayabliPayInFailureMessage.text(
                for: PayabliGenericError(type: .rateLimited, reason: "Too many requests"),
                operation: .capture
            ),
            "The payment couldn't be completed. Please try again."
        )
    }
}
