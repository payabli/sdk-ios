@testable import PayabliSDKPayIn
import SwiftUI
import UIKit
import XCTest

/// Rendered forms, since the summary's rows are SwiftUI text a hosted test cannot read back: what is
/// measured is how much room the drawn rows take.
@MainActor
final class PaymentSummaryRenderTests: XCTestCase {
    func testEachDrawnRowTakesItsOwnLine() {
        let totalOnly = renderedHeight(PayabliPayInPaymentDetails(totalAmount: 12.34, currency: "USD"))
        let withFee = renderedHeight(PayabliPayInPaymentDetails(totalAmount: 12.34, serviceFee: 0.5, currency: "USD"))
        let withBoth = renderedHeight(
            PayabliPayInPaymentDetails(totalAmount: 12.34, serviceFee: 0.5, surchargeFee: 0.31, currency: "USD")
        )

        XCTAssertGreaterThan(withFee, totalOnly, "a fee adds the Amount and Fee rows above Total")
        XCTAssertGreaterThan(withBoth, withFee, "a surcharge adds its own row")
    }

    func testAStoredMethodDrawsNoSummary() {
        let capture = renderedHeight(PayabliPayInPaymentDetails(totalAmount: 12.34, currency: "USD"))
        let store = renderedHeight(nil, operation: .storePaymentMethod)

        XCTAssertGreaterThan(capture, store, "a capture draws its Total, a stored method draws no summary")
    }

    private func renderedHeight(
        _ paymentDetails: PayabliPayInPaymentDetails?,
        operation: PayabliPayInOperation = .capture
    ) -> CGFloat {
        let component = flowOnSession(
            operation: operation,
            requestConfiguration: paymentDetails.map { PayabliPayInRequestConfiguration(paymentDetails: $0) }
        )
        let host = PayInUIKitHostingSupport.host(PayabliPayInView(
            component: component,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card]),
            onCompleted: { _ in }
        ))
        PayInUIKitHostingSupport.waitForRenderedSubviews(in: host.view)
        return host.sizeThatFits(in: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
    }
}
