import SwiftUI

/// The latest answer from each token probe, shared by every screen that runs one
/// or derives a step from one.
///
/// Each screen used to keep its own copy, which made the answer unshareable in
/// both directions. A probe run on the Configuration tab could not reach the tab
/// whose sequence reads it, and a tab whose backend step had already finished
/// renders no content, so its own probe button was gone. Between them a failing
/// probe could not be made to outrank an earlier success anywhere except a unit
/// test.
///
/// Two probes, because they are two endpoints. The card-present partner token is
/// what Tap to Pay attests with; the card-not-present token is what both PayIn
/// tabs submit with, and `Secrets.fetchPaymentCaptureAccessToken` forwards to
/// `fetchPaymentMethodAccessToken`, so one answer covers both of those tabs.
///
/// Each probe reports only *that* a token arrived. Never the token.
@MainActor
final class TokenProbeResults: ObservableObject {
    @Published private(set) var cardPresent = ""
    @Published private(set) var cardNotPresent = ""

    func probeCardPresent() async {
        cardPresent = "Checking…"
        do {
            _ = try await Secrets.fetchAccessToken()
            cardPresent = "✓ Card-present token endpoint returned a token"
        } catch {
            cardPresent = "✗ Card-present token endpoint failed: \(error.localizedDescription)"
        }
    }

    func probeCardNotPresent() async {
        cardNotPresent = "Checking…"
        do {
            _ = try await Secrets.fetchPaymentMethodAccessToken()
            cardNotPresent = "✓ Card-not-present token endpoint returned a token"
        } catch {
            cardNotPresent = "✗ Card-not-present token endpoint failed: \(error.localizedDescription)"
        }
    }
}
