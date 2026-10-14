import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

@MainActor
final class PayabliPayInReadTransactionTests: XCTestCase {
    func testAReadIsRefusedBeforeAnythingIsSent() async {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = PayInFixture.makeFlow(transport: transport, key: "unused")

        do {
            _ = try await flow.readTransaction("trans-1")
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual((error as? any PayabliError)?.type, .sdkInternalError)
        }
        XCTAssertEqual(transport.count, 0)
    }
}
