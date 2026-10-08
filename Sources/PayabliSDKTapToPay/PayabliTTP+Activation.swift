import Foundation
import PayabliSDKCore

// MARK: - Device activation (PRD §9.7)

@MainActor
public extension PayabliTTP {
    /// Activate a pending device using an activation code supplied by the
    /// partner out-of-band (e.g. an admin dashboard).
    ///
    /// Emits `.activationStarted` on entry, `.activationCompleted` on success,
    /// or `.activationFailed(error:)` on any failure path. A revoked attestation
    /// or a registration replaced since its activation ID was read lands
    /// `.failed(reason: .deviceSetupRequired)`, and `initialize()` sets the device
    /// up again; `.sessionExpired` is also emitted for a revoked attestation.
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
            let failure = TapToPayError(
                type: .deviceSetupRequired,
                reason: "The registration changed since its activation ID was read; initialize again",
                detail: nil
            )
            markError(failure)
            syncPublished()
            multicaster.emit(.activationFailed(error: TapToPayErrorTranslation.eventName(of: failure)))
            throw failure
        } catch let err as PayabliTTPError {
            // The attestation service already cleared local cache for the
            // revoked case, so the next `initialize()` attests cold.
            if case .attestationRevoked = err {
                markError(err)
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
