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
                capture: error.capture,
                retryAfter: retryAfter(of: error)
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

    /// What a charge's failure reaches a host as. Once the reader has been asked for a card, a code saying
    /// nothing was sent becomes `paymentOutcomeUnknown`, because the sale may already be taken, and a failure
    /// that names no payment takes the charge's.
    static func hostError(for error: Error, chargeOf paymentTransId: String?, askedForCard: Bool) -> Error {
        guard let failure = hostError(for: error) as? TapToPayError else { return error }
        let claimsNothingWasSent = failure.type == .validation || failure.type == .sdkInternalError
        let type = askedForCard && claimsNothingWasSent ? PayabliErrorType.paymentOutcomeUnknown : failure.type
        let namesNoPayment = failure.paymentTransId == nil
        return TapToPayError(
            type: type,
            reason: type == failure.type ? failure.reason : type.message,
            detail: failure.detail,
            paymentTransId: failure.paymentTransId ?? paymentTransId,
            capture: namesNoPayment && askedForCard ? .unknown : failure.capture,
            retryAfter: failure.retryAfter
        )
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

    /// The wait a failed close was given, which is the only case that carries one.
    private static func retryAfter(of error: PayabliTTPError) -> TimeInterval? {
        guard case let .updateFailed(_, _, _, retryAfter) = error else { return nil }
        return retryAfter
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
             let .updateFailed(reason, _, _, _):
            reason
        case .notInitialized, .invalidState, .notReady, .devicePendingActivation, .tokenExpired,
             .termsNotAccepted, .readerOSVersionNotSupported, .cardDeclined, .outcomeUnknown:
            nil
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

/// How far a charge got, which decides what its failure tells a host.
@MainActor
final class ChargeProgress {
    var paymentTransId: String?
    var askedForCard = false
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
