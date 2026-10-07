import Foundation
import PayabliSDKCore

/// The one table that decides the catalog entry a host receives for a card-present failure.
///
/// Every public card-present call passes its failure through ``hostError(for:)``, so a host catches
/// ``TapToPayError`` and nothing else. A `CancellationError` passes through unchanged.
enum TapToPayErrorTranslation {
    static func hostError(for error: Error) -> Error {
        switch error {
        case is CancellationError:
            return error
        case let error as TapToPayError:
            return error
        case let error as PayabliTTPError:
            let type = catalogType(of: error)
            return TapToPayError(
                type: type,
                reason: type.message,
                detail: serviceText(of: error),
                paymentTransId: error.paymentTransId,
                capture: error.capture
            )
        case let error as any PayabliError:
            return TapToPayError(
                type: error.type,
                reason: error.reason,
                detail: displayedDetail(of: error),
                retryAfter: (error as? PayabliRetryAfter)?.retryAfter
            )
        default:
            return TapToPayError(type: .unknown, reason: PayabliErrorType.unknown.message, detail: nil)
        }
    }

    /// The catalog wire name `error` reaches a host under, which is what a card-present event carries.
    /// A cancellation reaches a host as itself and has no entry, so its event reads `USER_CANCELLED`.
    static func eventName(of error: Error) -> String {
        guard let hostError = hostError(for: error) as? TapToPayError else {
            return PayabliErrorType.userCancelled.rawValue
        }
        return hostError.type.rawValue
    }

    // swiftlint:disable cyclomatic_complexity

    /// One branch per case, with no `default`, so a case added without an entry stops this compiling. A
    /// case collecting causes that do not share a code reports `unknown`.
    static func catalogType(of error: PayabliTTPError) -> PayabliErrorType {
        switch error {
        case .notInitialized:
            return .sessionNotInitialized
        case .invalidState:
            return .validation
        case .notReady:
            return .terminalNotReady
        case .devicePendingActivation:
            return .devicePendingActivation
        case .attestationRevoked:
            return .deviceSetupRequired
        case let .readerSetupFailed(reason, _) where isCancellation(reason),
             let .nfcFailed(reason, _) where isCancellation(reason):
            return .userCancelled
        case .attestationFailed, .configFailed, .activationFailed, .readerSetupFailed, .initiateFailed:
            return .unknown
        case .nfcFailed:
            return .tapNotCompleted
        case .updateFailed:
            return .paymentNotClosed
        case .tokenExpired:
            return .tokenExpired
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

    /// Everything a core error shows after its reason: its detail, and the field errors or the payer's next
    /// step some of them add.
    private static func displayedDetail(of error: any PayabliError) -> String? {
        guard let shown = error.errorDescription, shown != error.reason else { return error.detail }
        for separator in [" · ", ": "] where shown.hasPrefix(error.reason + separator) {
            return String(shown.dropFirst(error.reason.count + separator.count))
        }
        return error.detail
    }

    /// A person dismissed the platform's sheet. The reader marks it at the start of the case's reason.
    private static func isCancellation(_ reason: String) -> Bool {
        reason.hasPrefix(FiservCardReader.cancellationReasonPrefix)
    }

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
    func reportingToHost<Result>(_ work: () async throws -> Result) async throws -> Result {
        do {
            return try await work()
        } catch {
            throw TapToPayErrorTranslation.hostError(for: error)
        }
    }
}
