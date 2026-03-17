import Foundation
@testable import PayabliTTP

final class MockCardReader: CardReading {

    var isSessionActive: Bool = false
    var configureCalled = false
    var requestSessionTokenCalled = false
    var isAccountLinkedResult = true
    var linkAccountCalled = false
    var initializeSessionCalled = false
    var chargeCalled = false

    var chargeResult: [String: Any] = [
        "gatewayResponse": ["transactionState": "CAPTURED"],
        "transactionId": "fiserv-txn-123"
    ]

    var shouldFailCharge = false
    var shouldFailSetup = false

    func configure(with config: ConfigResponse) throws {
        configureCalled = true
        if shouldFailSetup {
            throw PayabliTTPError.fiservError("Mock configure failure")
        }
    }

    func requestSessionToken() async throws {
        requestSessionTokenCalled = true
        if shouldFailSetup {
            throw PayabliTTPError.fiservError("Mock session token failure")
        }
    }

    func isAccountLinked() async throws -> Bool {
        isAccountLinkedResult
    }

    func linkAccount() async throws {
        linkAccountCalled = true
    }

    func initializeSession() async throws {
        initializeSessionCalled = true
        if shouldFailSetup {
            throw PayabliTTPError.fiservError("Mock session failure")
        }
        isSessionActive = true
    }

    func charge(amount: Decimal, merchantTransactionId: String?) async throws -> [String: Any] {
        chargeCalled = true
        if shouldFailCharge {
            throw PayabliTTPError.fiservError("Mock NFC tap failed")
        }
        return chargeResult
    }
}
