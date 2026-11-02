import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

// MARK: - A refused customer

@available(iOS 16.7, *)
extension TTPChargeKeyTests {
    func testARefusedCustomerOnAResentKeyStaysUnknownAndKeepsTheKey() async throws {
        let (ttp, provider) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        Self.wire.initiateRefusesCustomer = true

        let refused = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }
        Self.wire.initiateRefusesCustomer = false

        XCTAssertEqual(refused?.refusal, .customerDataRefused(requiredFields: ["customerNumber"]))
        XCTAssertEqual(refused?.capture, .unknown)
        XCTAssertEqual(provider.startReadingCalls, 1, "the refused resend asked for a card")
        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }
        XCTAssertEqual(Self.wire.keys[2], Self.wire.keys[0], "the refusal let the held key go")
    }

    func testARefusedCustomerOnAFreshKeyIsNotChargedAndSettlesTheKey() async throws {
        let (ttp, _) = try await makeReadyTTP()
        Self.wire.initiateRefusesCustomer = true

        let refused = await failure { try await ttp.charge(paymentDetails: Self.details) }
        Self.wire.initiateRefusesCustomer = false

        XCTAssertEqual(refused?.refusal, .customerDataRefused(requiredFields: ["customerNumber"]))
        XCTAssertEqual(refused?.capture, .notCharged)
        _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)
        XCTAssertNotEqual(Self.wire.keys[1], Self.wire.keys[0], "the refused opening's key was kept")
    }
}
