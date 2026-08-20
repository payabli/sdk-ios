import Foundation
import PayabliSDKCore

// MARK: - Device activation (PRD §9.7)

@MainActor
public extension PayabliTTP {
    /// Activate a pending device using an activation code supplied by the
    /// partner out-of-band (e.g. an admin dashboard).
    ///
    /// Emits `.activationStarted` on entry, `.activationCompleted` on success,
    /// or `.activationFailed(error:)` on any failure path. On
    /// `.attestationRevoked` the session is reset to `.idle` (not `.error`)
    /// so the caller can immediately re-run `initialize()` for a fresh cold
    /// attestation — `.sessionExpired` is also emitted in that sub-case.
    func activateDevice(activationCode: String) async throws {
        guard sessionState == .pendingActivation else {
            throw PayabliTTPError.invalidState(
                current: sessionState,
                attempted: "activateDevice"
            )
        }
        multicaster.emit(.activationStarted)
        do {
            try await attestation.activateDevice(activationCode: activationCode, entry: entryPoint)
            _ = sessionManager.transition(to: .idle)
            syncPublished()
            multicaster.emit(.activationCompleted)
        } catch let err as PayabliTTPError {
            // The attestation service already cleared local cache for the
            // revoked case. Reset the session to `.idle` (not `.error`) so
            // the caller can immediately re-run `initialize()` which will
            // perform a fresh cold-path attestation.
            if case .attestationRevoked = err {
                _ = sessionManager.transition(to: .idle)
                syncPublished()
                multicaster.emit(.sessionExpired)
                multicaster.emit(.activationFailed(error: ErrorSummary.of(err)))
                throw err
            }
            sessionManager.markError(err)
            syncPublished()
            multicaster.emit(.activationFailed(error: ErrorSummary.of(err)))
            throw err
        } catch {
            sessionManager.markError(error)
            syncPublished()
            // The reason is what the caller and the screen get, so it is the
            // error's parsed description rather than a rendering of its fields.
            let mapped = PayabliTTPError.activationFailed(reason: error.localizedDescription)
            multicaster.emit(.activationFailed(error: ErrorSummary.of(mapped)))
            throw mapped
        }
    }

    /// `@objc` companion to `activateDevice(activationCode:)` for ObjC /
    /// MAUI / Flutter / RN consumers. `completion(nil)` on success,
    /// `completion(NSError)` on failure (domain `"com.payabli.ttp"` for
    /// typed `PayabliTTPError`s).
    ///
    /// The completion handler is always invoked on the main thread because
    /// the entire `PayabliTTP` surface is `@MainActor`.
    @objc func activateDevice(
        activationCode: String,
        completion: @escaping (NSError?) -> Void
    ) {
        Task { @MainActor in
            do {
                try await self.activateDevice(activationCode: activationCode)
                completion(nil)
            } catch {
                completion(error.toPayabliNSError())
            }
        }
    }
}
