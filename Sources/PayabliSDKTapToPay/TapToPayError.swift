import Foundation
import PayabliSDKCore

/// A card-present failure. One type for every cause: what varies is ``code``, whose
/// ``PayabliErrorCode/category`` says what to do about it.
///
/// `paymentTransId` and `capture` describe the payment a failure belongs to, and say no money moved
/// for one that belongs to none.
public struct TapToPayError: PayabliError {
    public let code: PayabliErrorCode
    public let reason: String
    public let detail: String?
    public let paymentTransId: String?
    public let capture: PayabliTTPCapture

    package init(
        code: PayabliErrorCode,
        reason: String,
        detail: String?,
        paymentTransId: String? = nil,
        capture: PayabliTTPCapture = .notCharged
    ) {
        self.code = code
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
        code.number
    }

    public var errorUserInfo: [String: Any] {
        var info: [String: Any] = [
            NSLocalizedDescriptionKey: errorDescription ?? reason,
            "PayabliErrorCode": code.rawValue,
            "capture": capture.rawValue
        ]
        if let paymentTransId {
            info["paymentTransId"] = paymentTransId
        }
        return info
    }
}
