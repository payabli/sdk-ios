import Combine
import Foundation
import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

final class PaymentMethodSwitchWhilePendingTests: XCTestCase {
    @MainActor
    func testASwitchWhileASubmissionIsPendingLeavesTheMethodAndItsValuesAndTheRequestOnTheCard() async throws {
        let transport = HeldTransport()
        let viewModel = PayabliPayInViewModel(
            component: PayabliPayIn(entryPoint: "entry", environment: .sandbox, transport: transport),
            operation: .capture(PayabliPayInRequestConfiguration(
                paymentDetails: PayabliPayInPaymentDetails(totalAmount: 15)
            )),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card, .bankAccount], defaultMethod: .card)
        )
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "02/30"
        viewModel.cardCvv = "123"
        viewModel.cardZip = "33139"
        let submission = Task { try await viewModel.submit() }
        await transport.waitForRequest()

        var published: [PayabliPayInMethodType] = []
        let watching = viewModel.$methodOnScreen.dropFirst().sink { published.append($0) }
        viewModel.selectedMethod = .bankAccount

        XCTAssertEqual(published, [])
        XCTAssertEqual(viewModel.selectedMethod, .card)
        XCTAssertFalse(viewModel.cardNumber.isEmpty, "the switch dropped what was typed for the method being sent")

        await transport.release()
        _ = try? await submission.value
        watching.cancel()

        let held = await transport.body
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(held)) as? [String: Any])
        let method = try XCTUnwrap(sent["paymentMethod"] as? [String: Any])
        XCTAssertEqual(method["method"] as? String, "card")
        XCTAssertEqual(published, [])
        XCTAssertEqual(viewModel.selectedMethod, .card)
    }

    @MainActor
    func testASwitchAfterTheSubmissionEndsIsTaken() async {
        let transport = HeldTransport()
        let viewModel = PayabliPayInViewModel(
            component: PayabliPayIn(entryPoint: "entry", environment: .sandbox, transport: transport),
            operation: .capture(PayabliPayInRequestConfiguration(
                paymentDetails: PayabliPayInPaymentDetails(totalAmount: 15)
            )),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card, .bankAccount], defaultMethod: .card)
        )
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "02/30"
        viewModel.cardCvv = "123"
        viewModel.cardZip = "33139"
        let submission = Task { try await viewModel.submit() }
        await transport.waitForRequest()
        await transport.release()
        _ = try? await submission.value

        viewModel.selectedMethod = .bankAccount

        XCTAssertEqual(viewModel.selectedMethod, .bankAccount)
    }

    /// The refusal is for the payer's switch. A configuration is the host's, and the method on screen
    /// and the fields drawn have to agree.
    @MainActor
    func testAReconfigurationThatDropsTheMethodWhilePendingMovesItAtOnce() async {
        let transport = HeldTransport()
        let component = PayabliPayIn(entryPoint: "entry", environment: .sandbox, transport: transport)
        let operation = PayabliPayInOperation.capture(PayabliPayInRequestConfiguration(
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 15)
        ))
        let viewModel = PayabliPayInViewModel(
            component: component,
            operation: operation,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card, .bankAccount], defaultMethod: .card)
        )
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "02/30"
        viewModel.cardCvv = "123"
        viewModel.cardZip = "33139"
        let submission = Task { try await viewModel.submit() }
        await transport.waitForRequest()

        viewModel.update(
            component: component,
            operation: operation,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.bankAccount]),
            labels: PayabliPayInFormLabels()
        )
        XCTAssertEqual(viewModel.selectedMethod, .bankAccount)
        XCTAssertEqual(viewModel.effectiveSelectedMethod, viewModel.selectedMethod)

        await transport.release()
        _ = try? await submission.value

        XCTAssertEqual(viewModel.selectedMethod, .bankAccount)
    }
}

/// Holds the first call until released, then refuses it, so a test can act while a submission is pending.
private actor HeldTransport: PayabliTransport {
    private(set) var body: Data?
    private var requested = false
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<Void, Never>?

    func waitForRequest() async {
        guard !requested else { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func release() {
        responseWaiter?.resume()
        responseWaiter = nil
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        body = request.body
        requested = true
        requestWaiter?.resume()
        requestWaiter = nil
        await withCheckedContinuation { responseWaiter = $0 }
        return PayabliResponse(statusCode: 400, headers: [:], body: Data(#"{"isSuccess":false}"#.utf8))
    }

    func performV2<T: Decodable & Sendable>(
        _: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        throw URLError(.notConnectedToInternet)
    }
}
