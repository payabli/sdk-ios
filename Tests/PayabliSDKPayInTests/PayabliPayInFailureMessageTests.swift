import Foundation
import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

final class PayabliPayInFailureMessageTests: XCTestCase {
    func testEachCategoryDrawsItsMessage() {
        for category in PayabliErrorCategory.allCases {
            let expected = switch category {
            case .declined: "The payment was declined. Try another payment method."
            case .retryLater: "The payment couldn't be completed. Please try again."
            case .outcomeUnknown: "This payment may have gone through. Check before paying again."
            default: "The payment couldn't be completed."
            }
            XCTAssertEqual(PayabliPayInFailureMessage.text(for: category), expected, "\(category)")
        }
    }

    func testAnErrorOutsideTheCatalogDrawsTheDefaultMessage() {
        XCTAssertEqual(
            PayabliPayInFailureMessage.text(for: URLError(.notConnectedToInternet)),
            "The payment couldn't be completed."
        )
    }

    func testACatalogErrorDrawsItsCategorysMessage() {
        XCTAssertEqual(
            PayabliPayInFailureMessage.text(for: PayabliGenericError(type: .rateLimited, reason: "Too many requests")),
            "The payment couldn't be completed. Please try again."
        )
    }
}
