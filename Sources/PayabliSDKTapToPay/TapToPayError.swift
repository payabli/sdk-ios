import Foundation
import PayabliSDKCore

/// A card-present failure. One type for every cause: what varies is ``type``, whose
/// ``PayabliErrorType/category`` says what to do about it.
///
/// `paymentTransId` and `capture` describe the payment a failure belongs to, and say no money moved
/// for one that belongs to none.
public struct TapToPayError: PayabliError {
    public let type: PayabliErrorType
    public let reason: String
    public let detail: String?
    public let paymentTransId: String?
    public let capture: PayabliTTPCapture

    package init(
        type: PayabliErrorType,
        reason: String,
        detail: String?,
        paymentTransId: String? = nil,
        capture: PayabliTTPCapture = .notCharged
    ) {
        self.type = type
        self.reason = reason
        self.detail = detail
        self.paymentTransId = paymentTransId
        self.capture = capture
    }
}

/// Bridges to `NSError` with the catalog number as its code, so an Objective-C, MAUI, Flutter or React
/// Native caller branches on the same number telemetry reports.
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
        return info
    }
}
