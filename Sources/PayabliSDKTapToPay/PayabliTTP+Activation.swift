import Foundation
import PayabliSDKCore

// MARK: - Device activation

@available(iOS 16.7, *)
@MainActor
public extension PayabliTTP {
    /// Activate a pending device using an activation code supplied by the
    /// partner out-of-band (e.g. an admin dashboard).
    ///
    /// On success the session returns to `.idle` so the caller runs `initialize()`
    /// again. A device that has to be set up again lands
    /// `.failed(reason: .deviceSetupRequired)`, and `initialize()` sets it up.
    /// A call made during a charge waits for the charge to end.
    ///
    /// - Parameter activationCode: the code the partner issued out of band, e.g. from an admin dashboard.
    func activateDevice(activationCode: String) async throws {
        try await reportingToHost {
            try await runSessionSetup(.activate(code: activationCode)) { try await self.runActivateDevice(activationCode: activationCode) }
        }
    }

    private func runActivateDevice(activationCode: String) async throws {
        try requireLiveSession()
        guard case let .pendingActivation(activationId) = sessionState else {
            throw TapToPayError(type: .deviceNotPending, reason: PayabliErrorType.deviceNotPending.message, detail: nil)
        }
        // The service reads six digits and nothing else, so a code it cannot read is refused here rather than
        // sent: no answer the service could give changes what the code is.
        guard activationCode.count == 6, activationCode.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw PayabliTTPError.activationCodeMalformed
        }
        try await renewingRefusedToken(landsSecondRefusal: false) {
            try await self.sendActivation(activationCode: activationCode, activationId: activationId)
        }
    }

    private func sendActivation(activationCode: String, activationId: String) async throws {
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
            // A thrown TapToPayError marks itself, since it names the setup failure it is; anything else marks
            // the activation's failure, which leaves the session where it waits.
            let failure: Error = activationSendFailure(error)
            markError(error is TapToPayError ? error : mapped)
            syncPublished()
            throw failure
        }
    }

    /// What a failure to send the activation is thrown as, by its kind.
    ///
    /// A core error or a cancellation keeps its own code and its wait, and a request `URLSession` reported
    /// cancelled is a cancellation. A network refusal is the network's own failure; anything else is the SDK's.
    private func activationSendFailure(_ error: Error) -> Error {
        if error is any PayabliError || error is CancellationError {
            return error
        }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled {
                return CancellationError()
            }
            return PayabliGenericError(
                type: .networkError,
                reason: "Network request failed",
                underlying: urlError
            )
        }
        let nsError = error as NSError
        return TapToPayError(
            type: .sdkInternalError,
            reason: "The activation could not be sent",
            detail: "\(nsError.domain) \(nsError.code)"
        )
    }

    /// `@objc` companion to `activateDevice(activationCode:)` for ObjC /
    /// MAUI / Flutter / RN consumers. `completion(nil)` on success,
    /// `completion(NSError)` on failure, a ``TapToPayError`` with its catalog
    /// number as the code.
    ///
    /// The completion handler is always invoked on the main thread because
    /// the entire `PayabliTTP` surface is `@MainActor`.
    ///
    /// - Parameter activationCode: the code the partner issued out of band, e.g. from an admin dashboard.
    /// - Parameter completion: the error the activation failed with, or `nil` when it succeeded.
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
