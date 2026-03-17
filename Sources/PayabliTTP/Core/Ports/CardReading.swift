import Foundation

/// Port: NFC card reader for Tap to Pay.
/// Test adapter: MockCardReader.
protocol CardReading {
    var isSessionActive: Bool { get }

    func configure(with config: ConfigResponse) throws
    func requestSessionToken() async throws
    func isAccountLinked() async throws -> Bool
    func linkAccount() async throws
    func initializeSession() async throws
    func charge(amount: Decimal, merchantTransactionId: String?) async throws -> [String: Any]
}
