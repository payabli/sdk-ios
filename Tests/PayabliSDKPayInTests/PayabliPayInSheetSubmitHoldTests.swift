@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import SwiftUI
import UIKit
import XCTest

@MainActor
final class PayabliPayInSheetSubmitHoldTests: XCTestCase {
    func testTheSheetRefusesAnInteractiveDismissWhileASubmissionIsInFlight() async throws {
        let transport = HeldResponseTransport()
        let payIn = PayabliPayIn(entryPoint: "entry", environment: .sandbox, transport: transport)
        let host = UIHostingController(rootView: SubmitHoldSheetHarness(payIn: payIn))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        PayInUIKitHostingSupport.waitForPresentedViewController(from: host)
        let sheet = try XCTUnwrap(host.presentedViewController)
        XCTAssertFalse(sheet.isModalInPresentation, "the sheet opens dismissible")

        let submission = Task { try await payIn.capture(Self.cashCapture) }
        await transport.waitForRequest()
        waitUntil { sheet.isModalInPresentation }
        XCTAssertTrue(sheet.isModalInPresentation, "a swipe is refused while the capture is in flight")

        await transport.release()
        _ = try? await submission.value
        waitUntil { !sheet.isModalInPresentation }
        XCTAssertFalse(sheet.isModalInPresentation, "a swipe works again once the capture ended")
    }

    func testTheDismissButtonDoesNothingWhileASubmissionIsInFlight() async {
        let transport = HeldResponseTransport()
        let payIn = PayabliPayIn(entryPoint: "entry", environment: .sandbox, transport: transport)
        var isPresented = true
        let content = sheetContent(payIn: payIn, isPresented: Binding(get: { isPresented }, set: { isPresented = $0 }))

        let submission = Task { try await payIn.capture(Self.cashCapture) }
        await transport.waitForRequest()
        content.dismissUnlessSubmitting()
        XCTAssertTrue(isPresented, "the button is refused while the capture is in flight")

        await transport.release()
        _ = try? await submission.value
        content.dismissUnlessSubmitting()
        XCTAssertFalse(isPresented, "the button dismisses once the capture ended")
    }

    private static let cashCapture = PayabliPayInRequest(
        paymentMethod: .cash,
        options: PayabliPayInRequestConfiguration(paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10))
    )

    private func sheetContent(payIn: PayabliPayIn, isPresented: Binding<Bool>) -> PayabliPayInSheetContent {
        PayabliPayInSheetContent(
            isPresented: isPresented,
            payIn: payIn,
            operation: .storePaymentMethod(),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card]),
            labels: PayabliPayInFormLabels(),
            sheetConfiguration: PayabliPayInSheetConfiguration(),
            style: nil,
            onCompleted: { _ in },
            onFailed: { _ in },
            onMethodChanged: { _ in }
        )
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }
}

private struct SubmitHoldSheetHarness: View {
    @State private var isPresented = true
    let payIn: PayabliPayIn

    var body: some View {
        Text("Host")
            .payabliPayInSheet(
                isPresented: $isPresented,
                payIn: payIn,
                operation: .storePaymentMethod(),
                configuration: PayabliPayInFormConfiguration(allowedMethods: [.card]),
                onCompleted: { _ in },
                onFailed: { _ in },
                onMethodChanged: { _ in }
            )
    }
}

/// Holds the first request's response until ``release()``, so a submission stays in flight for as long as a
/// test needs it to. The response it then gives is refused, which ends the submission.
private actor HeldResponseTransport: PayabliTransport {
    private var requestArrived = false
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<Void, Never>?

    func waitForRequest() async {
        guard !requestArrived else { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func release() {
        responseWaiter?.resume()
        responseWaiter = nil
    }

    func perform(_: PayabliRequest) async throws -> PayabliResponse {
        requestArrived = true
        requestWaiter?.resume()
        requestWaiter = nil
        await withCheckedContinuation { responseWaiter = $0 }
        return PayabliResponse(statusCode: 500, headers: [:], body: Data("{}".utf8))
    }

    func performV2<T: Decodable & Sendable>(
        _: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        throw URLError(.badServerResponse)
    }
}
