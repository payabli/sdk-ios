import Foundation
@testable import PayabliSDKPayIn

#if canImport(PassKit) && os(iOS)
import PassKit

@MainActor
final class MockApplePayManager: ApplePayManager {
    static func canMakePayments() -> Bool { true }

    var result: Result<ApplePayToken, Error> = .success(
        ApplePayToken(
            paymentData: Data("encrypted_payment_data".utf8),
            network: "Visa",
            displayName: "Visa 1234"
        )
    )
    private(set) var presentedCount = 0

    func presentPaymentSheet(
        request: PayabliPaymentRequest,
        config: PayabliApplePayConfig
    ) async throws -> ApplePayToken {
        presentedCount += 1
        switch result {
        case .success(let token): return token
        case .failure(let err): throw err
        }
    }
}
#endif
