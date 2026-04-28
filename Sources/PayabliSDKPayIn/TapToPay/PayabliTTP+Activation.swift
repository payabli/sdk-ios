import Foundation
import PayabliSDKCore

// MARK: - Device activation (PRD §9.7)

@MainActor
extension PayabliTTP {

    /// Activate a pending device using an activation code supplied by the
    /// partner out-of-band (e.g. an admin dashboard).
    ///
    /// Emits `.activationStarted` on entry, `.activationCompleted` on success,
    /// or `.activationFailed(error:)` on any failure path. On
    /// `.attestationRevoked` the session is reset to `.idle` (not `.error`)
    /// so the caller can immediately re-run `initialize()` for a fresh cold
    /// attestation — `.sessionExpired` is also emitted in that sub-case.
    public func activateDevice(activationCode: String) async throws {
        guard sessionState == .pendingActivation else {
            throw PayabliTTPError.invalidState(
                current: sessionState,
                attempted: "activateDevice"
            )
        }
        multicaster.emit(.activationStarted)
        do {
            try await attestation.activateDevice(activationCode: activationCode, entry: entry)
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
                multicaster.emit(.activationFailed(error: String(describing: err)))
                throw err
            }
            sessionManager.markError(err)
            syncPublished()
            multicaster.emit(.activationFailed(error: String(describing: err)))
            throw err
        } catch {
            sessionManager.markError(error)
            syncPublished()
            let mapped = PayabliTTPError.activationFailed(reason: String(describing: error))
            multicaster.emit(.activationFailed(error: String(describing: mapped)))
            throw mapped
        }
    }
}
