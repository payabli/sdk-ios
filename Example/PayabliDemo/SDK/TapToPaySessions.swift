import Foundation
import PayabliSDKTapToPay

/// Where this app's card reader is built.
enum TapToPaySessions {
    /// The terminal the app runs on, built after `DemoSession` has started, so it runs on the
    /// session the card-not-present flows share. A canvas preview gets one too, which it never
    /// initializes, so it makes no network call and touches neither App Attest nor the reader.
    @MainActor
    static func terminal() async -> TapToPayTerminal {
        do {
            return TapToPayTerminal(try await PayabliTTP.create())
        } catch {
            preconditionFailure("The terminal could not be built: \(error)")
        }
    }
}
