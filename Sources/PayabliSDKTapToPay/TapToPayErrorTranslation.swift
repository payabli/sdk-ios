import Foundation
import PayabliSDKCore

/// The one table that decides the catalog entry a host receives for a card-present failure.
///
/// Every public card-present call passes its failure through ``hostError(for:raisedBy:)``, so a host
/// catches ``TapToPayError`` and nothing else. Cancellation is the exception, and reaches the caller as
/// `CancellationError`.
enum TapToPayErrorTranslation {
    /// The public call a failure surfaced from. One internal case can mean different causes depending on
    /// the call that met it.
    enum Call {
        case initialize
        case reinitialize
        case charge
        case activateDevice
        case terms
    }

    static func hostError(for error: Error, raisedBy call: Call) -> Error {
        switch error {
        case is CancellationError:
            return error
        case let error as TapToPayError:
            return error
        case let error as PayabliTTPError:
            let type = catalogType(of: error, raisedBy: call)
            return TapToPayError(
                type: type,
                reason: type.message,
                detail: serviceText(of: error),
                paymentTransId: error.paymentTransId,
                capture: error.capture
            )
        case let error as any PayabliError:
            return TapToPayError(type: error.type, reason: error.reason, detail: error.detail)
        default:
            return TapToPayError(type: .unknown, reason: PayabliErrorType.unknown.message, detail: nil)
        }
    }

    // swiftlint:disable cyclomatic_complexity

    /// One branch per case, with no `default`, so a case added without an entry stops this compiling.
    static func catalogType(of error: PayabliTTPError, raisedBy call: Call) -> PayabliErrorType {
        switch error {
        case .notInitialized:
            return .sessionNotInitialized
        case .invalidState:
            return call == .activateDevice ? .deviceNotPending : .validation
        case .notReady:
            return .terminalNotReady
        case .devicePendingActivation:
            return .devicePendingActivation
        case .attestationRevoked:
            return .deviceSetupRequired
        case .attestationFailed:
            return .deviceSetupRefused
        case .configFailed:
            return .entryPointRefused
        case .readerSetupFailed:
            return .readerUnavailable
        case .nfcFailed:
            return .tapNotCompleted
        case .initiateFailed:
            return .paymentNotOpened
        case .updateFailed:
            return .paymentNotClosed
        case .tokenExpired:
            return .tokenExpired
        case .activationFailed:
            return .activationCodeIncorrect
        case .networkError:
            return .networkError
        case .termsNotAccepted:
            return .termsNotAccepted
        case .readerOSVersionNotSupported:
            return .deviceOSUnsupported
        case .cardDeclined:
            return .cardDeclined
        case .outcomeUnknown:
            return .paymentOutcomeUnknown
        }
    }

    // swiftlint:enable cyclomatic_complexity

    /// The service's or the reader's own words, which a host shows beside the fixed message.
    private static func serviceText(of error: PayabliTTPError) -> String? {
        let text: String? = switch error {
        case let .attestationRevoked(reason),
             let .attestationFailed(reason),
             let .configFailed(reason),
             let .initiateFailed(reason),
             let .activationFailed(reason),
             let .networkError(reason),
             let .readerSetupFailed(reason, _),
             let .nfcFailed(reason, _),
             let .updateFailed(reason, _, _):
            reason
        case .notInitialized, .invalidState, .notReady, .devicePendingActivation, .tokenExpired,
             .termsNotAccepted, .readerOSVersionNotSupported, .cardDeclined, .outcomeUnknown:
            nil
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

extension PayabliTTP {
    /// Runs one public call, handing a host its failure as ``TapToPayError``.
    func reportingToHost<Result>(
        _ call: TapToPayErrorTranslation.Call,
        _ work: () async throws -> Result
    ) async throws -> Result {
        do {
            return try await work()
        } catch {
            throw TapToPayErrorTranslation.hostError(for: error, raisedBy: call)
        }
    }
}
