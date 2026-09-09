import Foundation
import PayabliSDKCore

// MARK: - Contactless payment terms

@MainActor
public extension PayabliTTP {
    /// Checks whether the merchant has accepted the terms required before this
    /// device will take a contactless payment.
    ///
    /// On iOS those terms are Apple's, held by the operating system and shown in
    /// a sheet the merchant signs off. The platform is the only authority on
    /// whether they have been accepted, which is why this asks it on every call
    /// rather than returning something the SDK remembered. Acceptance can also be
    /// granted or withdrawn outside this app, so a cached answer goes stale
    /// without anything failing. The underlying platform reader calls this state
    /// account linking, and `isAccountLinked` is the symbol to search for when
    /// reading Apple's documentation.
    ///
    /// No charge can be taken until this answers `true`.
    ///
    /// - Returns: `true` when the merchant has accepted.
    /// - Throws: `PayabliTTPError.readerSetupFailed(reason:)` when there is no
    ///   reader to ask — which is a different answer from `false`, and a caller
    ///   showing a terms screen should tell them apart.
    func areTermsAccepted() async throws -> Bool {
        try await provider.areTermsAccepted()
    }

    /// `@objc` companion to `areTermsAccepted()` for ObjC / MAUI / Flutter / RN
    /// consumers. Bridges the `async throws` Swift method to a callback-based
    /// signature: `completion(accepted, nil)` on success, `completion(false,
    /// NSError)` on failure (domain `"com.payabli.ttp"` for typed
    /// `PayabliTTPError`s).
    ///
    /// `false` on the failure path is the bridging default and never an answer.
    /// Read the error first; the two cases are only distinguishable by it.
    ///
    /// The completion handler is always invoked on the main thread because the
    /// entire `PayabliTTP` surface is `@MainActor`.
    @objc func areTermsAccepted(
        completion: @escaping (Bool, NSError?) -> Void
    ) {
        Task { @MainActor in
            do {
                let accepted = try await self.areTermsAccepted()
                completion(accepted, nil)
            } catch {
                completion(false, error.toPayabliNSError())
            }
        }
    }
}
