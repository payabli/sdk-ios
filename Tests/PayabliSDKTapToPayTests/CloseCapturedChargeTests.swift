@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

@available(iOS 16.7, *)
@MainActor
final class CloseCapturedChargeTests: XCTestCase {
    private final class TokenRequests: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int {
            lock.withLock { count }
        }

        func record() {
            lock.withLock { count += 1 }
        }
    }

    private let tokenRequests = TokenRequests()

    private func makeTerminal() throws -> PayabliTTP {
        let requests = tokenRequests
        let config = try PayabliConfig(
            entryPoint: "demo",
            environment: .sandbox,
            tokenProvider: {
                requests.record()
                return "token"
            }
        )
        return PayabliTTP(
            session: PayabliSession(config: config),
            provider: MockTapToPayProvider(),
            attestation: MockDeviceAttestationService()
        )
    }

    func testAnUnconfirmedCloseIsPaymentNotClosedNamingThePaymentWithItsCaptureUnknown() async throws {
        let terminal = try makeTerminal()

        do {
            try await terminal.closeCapturedCharge(paymentTransId: "TXN-7")
            XCTFail("an unconfirmed close returned normally")
        } catch let failure as TapToPayError {
            XCTAssertEqual(failure.type, .paymentNotClosed)
            XCTAssertEqual(failure.errorCode, 3022)
            XCTAssertEqual(failure.paymentTransId, "TXN-7")
            XCTAssertEqual(failure.capture, .unknown)
        }
        XCTAssertEqual(tokenRequests.value, 0, "a close that is not sent asks for no token")
    }

    func testTheObjectiveCCloseCompletesOnTheMainThreadWithTheCatalogNumberAndThePayment() async throws {
        let terminal = try makeTerminal()
        let completed = expectation(description: "completion")
        var received: NSError?
        var onMain = false

        terminal.closeCapturedCharge("TXN-7") { error in
            received = error
            onMain = Thread.isMainThread
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 5)

        let error = try XCTUnwrap(received)
        XCTAssertTrue(onMain)
        XCTAssertEqual(error.domain, TapToPayError.errorDomain)
        XCTAssertEqual(error.code, 3022)
        XCTAssertEqual(error.userInfo["paymentTransId"] as? String, "TXN-7")
        XCTAssertEqual(error.userInfo["capture"] as? Int, PayabliTTPCapture.unknown.rawValue)
    }
}
