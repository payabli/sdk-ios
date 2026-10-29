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
        case let refusal as ActivationRefusal:
            return refusal.hostError
        case let refusal as CustomerDataRefusal:
            return TapToPayError(
                type: refusal.type,
                reason: refusal.reason,
                detail: displayedDetail(of: refusal.validation),
                refusal: .customerDataRefused(requiredFields: refusal.requiredFields)
            )
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

    /// What a charge's failure reaches a host as. Once a card is asked for, a code saying nothing was sent becomes
    /// `paymentOutcomeUnknown`, except the reader's own guard. A failure naming no payment takes the charge's, and a
    /// resent key or a refused retry of a held sale names an earlier charge, so neither reports not charged.
    ///
    /// - Parameter error: what the charge threw, before it was translated for the host.
    /// - Parameter paymentTransId: the charge's payment, which a failure naming none takes.
    /// - Parameter askedForCard: whether the reader was already asked for a card.
    /// - Parameter resentKey: whether the charge resent a key held for an earlier one.
    /// - Parameter retriesHeldSale: whether a retry refused before reserving its key describes a held sale.
    /// - Returns: the failure a host receives, with its catalog entry.
    static func hostError(
        for error: Error,
        chargeOf paymentTransId: String?,
        askedForCard: Bool,
        resentKey: Bool = false,
        retriesHeldSale: Bool = false
    ) -> Error {
        guard let failure = hostError(for: error) as? TapToPayError else { return error }
        let claimsNothingWasSent = failure.type == .validation || failure.type == .sdkInternalError
        let readerTouchedNoCard = if case .guardFailed = error as? PayabliTTPError {
            true
        } else {
            false
        }
        let type: PayabliErrorType = if !askedForCard, resentKey, error is ChargeKeyRefusal {
            // The opening was refused as a repeat of an earlier charge that has not finished.
            .chargeNotFinished
        } else if askedForCard, claimsNothingWasSent, !readerTouchedNoCard {
            .paymentOutcomeUnknown
        } else {
            failure.type
        }
        let namesNoPayment = failure.paymentTransId == nil
        let capture: PayabliTTPCapture = namesNoPayment && askedForCard ? .unknown : failure.capture
        return TapToPayError(
            type: type,
            reason: type == failure.type ? failure.reason : type.message,
            detail: failure.detail,
            paymentTransId: failure.paymentTransId ?? paymentTransId,
            capture: (resentKey || retriesHeldSale) && capture == .notCharged ? .unknown : capture,
            retryAfter: failure.retryAfter,
            refusal: failure.refusal
        )
    }

    // swiftlint:disable cyclomatic_complexity

    /// One branch per case, with no `default`, so a case added without an entry stops this compiling. A
    /// case collecting causes that do not share a code reports `unknown`.
    ///
    /// - Parameter error: the failure whose catalog entry is chosen.
    /// - Returns: the catalog type a host receives the failure as.
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
        case .attestationRevoked, .deviceSetupRequired:
            return .deviceSetupRequired
        case .deviceSetupRefused:
            return .deviceSetupRefused
        case .entryPointRefused:
            return .entryPointRefused
        case let .readerSetupFailed(reason, _) where isCancellation(reason),
             let .nfcFailed(reason, _) where isCancellation(reason),
             let .readerUnavailable(reason, _, _) where isCancellation(reason):
            return .userCancelled
        case .attestationFailed, .configFailed, .activationFailed, .readerSetupFailed:
            return .unknown
        case .activationCodeMalformed:
            return .activationCodeMalformed
        case .readerCredentialsUnusable:
            return .readerCredentialsUnusable
        case .cardPresentNotEnabled:
            return .cardPresentNotEnabled
        case .readerHardwareUnsupported:
            return .deviceHardwareUnsupported
        case .guardFailed:
            return .sdkInternalError
        case .nfcFailed:
            return .tapNotCompleted
        case .updateFailed:
            return .paymentNotClosed
        case .paymentNotOpened:
            return .paymentNotOpened
        case .tokenExpired:
            return .tokenExpired
        case .networkError:
            return .networkError
        case .termsNotAccepted:
            return .termsNotAccepted
        case .readerOSVersionNotSupported:
            return .deviceOSUnsupported
        case .readerUnavailable:
            return .readerUnavailable
        case .readerDeviceRefused:
            return .readerDeviceRefused
        case .cardDeclined:
            return .cardDeclined
        case .outcomeUnknown:
            return .paymentOutcomeUnknown
        case .paymentNotTaken:
            return .paymentNotTaken
        }
    }

    // swiftlint:enable cyclomatic_complexity

    /// Everything a core error shows after its reason: its detail, and the field errors or the payer's next
    /// step some of them add.
    ///
    /// - Parameter error: the core error whose shown detail is extracted.
    /// - Returns: what the error shows after its reason, or its `detail` where it shows nothing.
    private static func displayedDetail(of error: any PayabliError) -> String? {
        guard let shown = error.errorDescription, shown != error.reason else { return error.detail }
        for separator in [" · ", ": "] where shown.hasPrefix(error.reason + separator) {
            return String(shown.dropFirst(error.reason.count + separator.count))
        }
        return error.detail
    }

    /// The wait a failed close was given, which is the only case that carries one.
    ///
    /// - Parameter error: the failure whose wait is read.
    /// - Returns: the wait the close was given, or `nil` where the case carries none.
    private static func retryAfter(of error: PayabliTTPError) -> TimeInterval? {
        guard case let .updateFailed(_, _, _, retryAfter) = error else { return nil }
        return retryAfter
    }

    /// A person dismissed the platform's sheet. The reader marks it at the start of the case's reason.
    ///
    /// - Parameter reason: the case's reason, whose start carries the marker.
    /// - Returns: whether the reason marks a dismissal.
    private static func isCancellation(_ reason: String) -> Bool {
        reason.hasPrefix(PayabliTTPError.cancellationReasonPrefix)
    }

    /// The service's or the reader's own words, which a host shows beside the fixed message.
    ///
    /// - Parameter error: the failure whose own words are read.
    /// - Returns: the words, or `nil` where the case carries none.
    private static func serviceText(of error: PayabliTTPError) -> String? {
        let text: String? = switch error {
        case let .attestationRevoked(reason),
             let .attestationFailed(reason),
             let .deviceSetupRequired(reason),
             let .deviceSetupRefused(reason),
             let .entryPointRefused(reason),
             let .configFailed(reason),
             let .paymentNotOpened(reason),
             let .activationFailed(reason),
             let .networkError(reason),
             let .readerSetupFailed(reason, _),
             let .readerUnavailable(reason, _, _),
             let .readerDeviceRefused(reason, _, _),
             let .guardFailed(reason, _),
             let .nfcFailed(reason, _),
             let .updateFailed(reason, _, _, _):
            reason
        case .notInitialized, .invalidState, .notReady, .devicePendingActivation, .tokenExpired,
             .termsNotAccepted, .readerOSVersionNotSupported, .readerHardwareUnsupported,
             .cardPresentNotEnabled, .activationCodeMalformed, .cardDeclined, .outcomeUnknown, .paymentNotTaken,
             .readerCredentialsUnusable:
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
    var reserved = false
    var resentKey = false
    var retriesHeldSale = false
}

@available(iOS 16.7, *)
extension PayabliTTP {
    /// Runs one public call, handing a host its failure as ``TapToPayError``.
    ///
    /// - Parameter work: the public call, run once.
    /// - Returns: what `work` answered.
    func reportingToHost<Result>(_ work: () async throws -> Result) async throws -> Result {
        do {
            return try await work()
        } catch {
            throw TapToPayErrorTranslation.hostError(for: error)
        }
    }
}
