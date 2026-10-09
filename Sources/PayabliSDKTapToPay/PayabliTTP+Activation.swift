import Foundation
import PayabliSDKCore

// MARK: - Device activation (PRD §9.7)

@MainActor
public extension PayabliTTP {
    /// Activate a pending device using an activation code supplied by the
    /// partner out-of-band (e.g. an admin dashboard).
    ///
    /// On success the session returns to `.idle` so the caller runs `initialize()`
    /// again. A device that has to be set up again lands
    /// `.failed(reason: .deviceSetupRequired)`, and `initialize()` sets it up.
    func activateDevice(activationCode: String) async throws {
        try await reportingToHost {
            try await runSessionSetup(.activate) { try await self.runActivateDevice(activationCode: activationCode) }
        }
    }

    private func runActivateDevice(activationCode: String) async throws {
        guard case let .pendingActivation(activationId) = sessionState else {
            throw TapToPayError(type: .deviceNotPending, reason: PayabliErrorType.deviceNotPending.message, detail: nil)
        }
        do {
            try await attestation.activateDevice(
                activationCode: activationCode,
                entry: entryPoint,
                activationId: activationId
            )
            _ = sessionManager.transition(to: .idle)
            syncPublished()
        } catch is ActivationRegistrationChanged {
            let failure = TapToPayError(
                type: .deviceSetupRequired,
                reason: "The registration changed since its activation ID was read; initialize again",
                detail: nil
            )
            markError(failure)
            syncPublished()
            throw failure
        } catch let signing as ActivationSigningFailed {
            markError(signing.hostError)
            syncPublished()
            throw signing.hostError
        } catch let refusal as ActivationRefusal {
            markError(refusal)
            syncPublished()
            throw refusal.hostError
        } catch let err as PayabliTTPError {
            markError(err)
            syncPublished()
            throw err
        } catch {
            // The reason is the error's parsed description rather than a rendering
            // of its fields.
            let mapped = PayabliTTPError.activationFailed(reason: error.localizedDescription)
            // A setup failure lands by its code, since no activation code repairs it.
            // Anything else marks the state from the activation's failure, which leaves
            // it where it is. A core error or a cancellation is thrown as it arrived, so
            // its code and its wait reach the caller.
            let failure: Error = error is any PayabliError || error is CancellationError ? error : mapped
            markError(error is TapToPayError ? error : mapped)
            syncPublished()
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
