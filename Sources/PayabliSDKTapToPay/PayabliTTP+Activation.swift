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
        try await reportingToHost {
            try await runSessionSetup(.activate) { try await self.runActivateDevice(activationCode: activationCode) }
        }
    }

    private func runActivateDevice(activationCode: String) async throws {
        guard case let .pendingActivation(activationId) = sessionState else {
            throw TapToPayError(type: .deviceNotPending, reason: PayabliErrorType.deviceNotPending.message, detail: nil)
        }
        multicaster.emit(.activationStarted)
        do {
            try await attestation.activateDevice(
                activationCode: activationCode,
                entry: entryPoint,
                activationId: activationId
            )
            _ = sessionManager.transition(to: .idle)
            syncPublished()
            multicaster.emit(.activationCompleted)
        } catch is ActivationRegistrationChanged {
            let failure = PayabliTTPError.activationFailed(
                reason: "The registration changed since its activation ID was read; initialize again"
            )
            _ = sessionManager.transition(to: .idle)
            syncPublished()
            multicaster.emit(.activationFailed(error: TapToPayErrorTranslation.eventName(of: failure)))
            throw failure
        } catch let err as PayabliTTPError {
            // The attestation service already cleared local cache for the
            // revoked case. Reset the session to `.idle` (not `.error`) so
            // the caller can immediately re-run `initialize()` which will
            // perform a fresh cold-path attestation.
            if case .attestationRevoked = err {
                _ = sessionManager.transition(to: .idle)
                syncPublished()
                multicaster.emit(.sessionExpired)
                multicaster.emit(.activationFailed(error: TapToPayErrorTranslation.eventName(of: err)))
                throw err
            }
            markError(err)
            syncPublished()
            multicaster.emit(.activationFailed(error: TapToPayErrorTranslation.eventName(of: err)))
            throw err
        } catch {
            // The reason is the error's parsed description rather than a rendering
            // of its fields.
            let mapped = PayabliTTPError.activationFailed(reason: error.localizedDescription)
            // The state is marked from the activation's failure. A core error or a
            // cancellation is thrown as it arrived, so its code and its wait reach
            // the caller.
            let failure: Error = error is any PayabliError || error is CancellationError ? error : mapped
            markError(mapped)
            syncPublished()
            multicaster.emit(.activationFailed(error: TapToPayErrorTranslation.eventName(of: failure)))
            throw failure
        }
    }

    /// `@objc` companion to `activateDevice(activationCode:)` for ObjC /
    /// MAUI / Flutter / RN consumers. `completion(nil)` on success,
    /// `completion(NSError)` on failure, a ``TapToPayError`` with its catalog
    /// number as the code.
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
