import Foundation
import PayabliSDKCore

/// A card-present failure. One type for every cause: what varies is ``type``, whose
/// ``PayabliErrorType/category`` says what to do about it.
///
/// `paymentTransId` and `capture` describe the payment a failure belongs to, and say no money moved
/// for one that belongs to none. `retryAfter` is the wait the service asked for, when it asked for one.
///
/// `refusal` is the charge's own refusal when this failure refused the charge, and nil when it did not.
/// It does not change ``type``: a host branches on `refusal` for what this failure asks them to do.
public struct TapToPayError: PayabliError, PayabliRetryAfter {
    public let type: PayabliErrorType
    public let reason: String
    public let detail: String?
    public let paymentTransId: String?
    public let capture: PayabliTTPCapture
    public let retryAfter: TimeInterval?
    public let refusal: TapToPayChargeRefusal?
    public let httpStatus: Int?
    public let rawCode: String?

    package init(
        type: PayabliErrorType,
        reason: String,
        detail: String?,
        paymentTransId: String? = nil,
        capture: PayabliTTPCapture = .notCharged,
        retryAfter: TimeInterval? = nil,
        refusal: TapToPayChargeRefusal? = nil,
        httpStatus: Int? = nil,
        rawCode: String? = nil
    ) {
        self.type = type
        self.reason = reason
        self.detail = detail
        self.paymentTransId = paymentTransId
        self.capture = capture
        self.retryAfter = retryAfter
        self.refusal = refusal
        self.httpStatus = httpStatus
        self.rawCode = rawCode
    }
}

extension TapToPayError {
    /// The same failure, carrying the status of the answer it was read from.
    ///
    /// - Parameter httpStatus: the status the answer came with.
    /// - Returns: a copy with `httpStatus` set and every other field unchanged.
    func carrying(httpStatus: Int) -> TapToPayError {
        TapToPayError(
            type: type,
            reason: reason,
            detail: detail,
            paymentTransId: paymentTransId,
            capture: capture,
            retryAfter: retryAfter,
            refusal: refusal,
            httpStatus: httpStatus,
            rawCode: rawCode
        )
    }
}

/// Bridges to `NSError` with the catalog number as its code, so an Objective-C caller branches on the same number
/// telemetry reports. `userInfo` carries ``PayabliError/answerUserInfo``, and a refused customer adds `refusal` and
/// `requiredFields`, every identifier the paypoint requires named by its ``PayabliTTPCustomerData`` property.
extension TapToPayError: CustomNSError {
    public static var errorDomain: String {
        "com.payabli.ttp"
    }

    public var errorCode: Int {
        code
    }

    public var errorUserInfo: [String: Any] {
        var info: [String: Any] = [
            NSLocalizedDescriptionKey: errorDescription ?? reason,
            "PayabliErrorType": type.rawValue,
            "capture": capture.rawValue
        ]
        if let paymentTransId {
            info["paymentTransId"] = paymentTransId
        }
        if let retryAfter {
            info["retryAfter"] = retryAfter
        }
        switch refusal {
        case let .customerDataRefused(requiredFields):
            info["refusal"] = "customerDataRefused"
            info["requiredFields"] = requiredFields
        case nil:
            break
        }
        info.merge(answerUserInfo) { _, answer in answer }
        return info
    }
}
