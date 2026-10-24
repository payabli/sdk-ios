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

    func testAnInterruptedSubmissionWarnsWhateverItsCausesCategory() {
        for type in [PayabliErrorType.rateLimited, .tokenExpired, .tokenProviderFailed, .validation] {
            let interrupted = PayabliPayInError.submissionInterrupted(
                type: type,
                causeType: "test",
                paymentTransId: nil,
                paymentReference: "p1"
            )

            XCTAssertEqual(
                PayabliPayInFailureMessage.text(for: interrupted, operation: .capture),
                "This payment may have gone through. Check before paying again.",
                "\(type)"
            )
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

    func testAnErrorOutsideTheCatalogDrawsTheOutcomeUnknownMessage() {
        XCTAssertEqual(
            PayabliPayInFailureMessage.text(for: URLError(.notConnectedToInternet), operation: .capture),
            "This payment may have gone through. Check before paying again."
        )
        XCTAssertEqual(
            PayabliPayInFailureMessage.text(for: URLError(.notConnectedToInternet), operation: .storePaymentMethod),
            "The payment method couldn't be saved."
        )
    }

    func testAnErrorOutsideTheCatalogDrawsTheHostsOutcomeUnknownWording() {
        XCTAssertEqual(
            PayabliPayInFailureMessage.text(
                for: URLError(.notConnectedToInternet),
                operation: .capture,
                labels: PayabliPayInFormLabels(outcomeUnknownMessage: "We can't tell whether that went through.")
            ),
            "We can't tell whether that went through."
        )
    }

    func testAnErrorOutsideTheCatalogDrawsTheOutcomeItIsReportedAs() {
        let failure = URLError(.notConnectedToInternet)
        let reported = PayabliGenericError(
            type: .unknown,
            reason: PayabliErrorType.unknown.message,
            underlying: RedactedCause(failure)
        )
        for operation in PayabliPayInOperation.allCases {
            XCTAssertEqual(
                PayabliPayInFailureMessage.text(for: failure, operation: operation),
                PayabliPayInFailureMessage.text(for: reported, operation: operation),
                "\(operation)"
            )
        }
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
