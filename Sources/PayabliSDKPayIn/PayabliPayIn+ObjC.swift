import Foundation
import PayabliSDKCore

/// The `NSError` domain every error this facade hands to an ObjC caller carries, whatever it wraps.
private let payInObjCErrorDomain = "com.payabli.payIn"

/// A payment method the service stored, for an Objective-C caller. Each field is
/// ``PayabliPayInStoredMethod``'s.
@objc(PayabliPayInStoredMethodObjC)
public final class PayabliPayInStoredMethodObjC: NSObject {
    @objc public let storedMethodId: String?
    @objc public let method: String
    @objc public let methodReferenceId: String?
    @objc public let customerId: NSNumber?

    init(_ method: PayabliPayInStoredMethod) {
        storedMethodId = method.storedMethodId
        self.method = Self.name(of: method.method)
        methodReferenceId = method.methodReferenceId
        customerId = method.customerId.map(NSNumber.init(value:))
        super.init()
    }

    private static func name(of method: PayabliPayInStoredMethodType) -> String {
        switch method {
        case .card: return "card"
        case .bankAccount: return "bankAccount"
        }
    }
}

/// A transaction read back, for an Objective-C caller. Each field is ``PayabliPayInTransaction``'s.
@objc(PayabliPayInTransactionObjC)
public final class PayabliPayInTransactionObjC: NSObject {
    @objc public let paymentTransId: String?
    @objc public let gatewayTransId: String?
    @objc public let orderId: String?
    @objc public let method: String?
    @objc public let transStatus: NSNumber?
    /// `initiated`, `authorized`, `captured`, `declined`, `voided`, `blocked`, `failed`, or `other` for a
    /// status this SDK does not name, whose number is ``transStatus``. `nil` when `transStatus` is.
    @objc public let status: String?
    @objc public let paypointId: NSNumber?
    @objc public let totalAmount: NSNumber?
    @objc public let netAmount: NSNumber?
    @objc public let feeAmount: NSNumber?
    @objc public let surchargeFee: NSNumber?

    /// - Parameter transaction: the transaction read back, whose fields this carries.
    init(_ transaction: PayabliPayInTransaction) {
        paymentTransId = transaction.paymentTransId
        gatewayTransId = transaction.gatewayTransId
        orderId = transaction.orderId
        method = transaction.method
        transStatus = transaction.transStatus.map(NSNumber.init(value:))
        status = transaction.status.map(Self.name(of:))
        paypointId = transaction.paypointId.map(NSNumber.init(value:))
        totalAmount = transaction.totalAmount.map(NSNumber.init(value:))
        netAmount = transaction.netAmount.map(NSNumber.init(value:))
        feeAmount = transaction.feeAmount.map(NSNumber.init(value:))
        surchargeFee = transaction.surchargeFee.map(NSNumber.init(value:))
        super.init()
    }

    private static func name(of status: PayabliPayInTransactionStatus) -> String {
        switch status {
        case .initiated: "initiated"
        case .authorized: "authorized"
        case .captured: "captured"
        case .declined: "declined"
        case .voided: "voided"
        case .blocked: "blocked"
        case .failed: "failed"
        case .other: "other"
        }
    }
}

@MainActor
@objc(PayabliPayInObjC)
public final class PayabliPayInObjC: NSObject {
    let component: PayabliPayIn

    @available(*, unavailable)
    override private init() {
        fatalError("unavailable")
    }

    init(component: PayabliPayIn) {
        self.component = component
        super.init()
    }

    /// Builds the facade on the installed session. Throws `sessionNotInitialized` when none is installed.
    ///
    /// - Returns: the facade, wrapping a flow built on the installed session.
    @objc public static func create() throws -> PayabliPayInObjC {
        guard let session = PayabliSession.current else {
            throw PayabliGenericError(type: .sessionNotInitialized, reason: "no session is initialized")
                .toPayabliPayInNSError()
        }
        return PayabliPayInObjC(component: PayabliPayIn(session: session))
    }

    /// Stores a payment method, as ``PayabliPayIn/storeMethod(_:)`` does.
    ///
    /// - Parameter request: the payment method to store, and what the request carries besides it.
    /// - Parameter completion: the method the service stored, or the error the store failed with.
    @objc(storeMethodWithRequest:completion:)
    public func storeMethod(
        _ request: PayabliPayInStoreRequestObjC,
        completion: @escaping (PayabliPayInStoredMethodObjC?, NSError?) -> Void
    ) {
        storeMethod(request.toSwift(), completion: completion)
    }

    /// Stores the payment method the request carries, closing its digit buffers at the task's end,
    /// on a result and a refusal alike: no host can reach them to close them itself.
    ///
    /// - Parameter request: the payment method to store, and what the request carries besides it.
    /// - Parameter completion: the method the service stored, or the error the store failed with.
    func storeMethod(
        _ request: PayabliPayInStoreRequest,
        completion: @escaping (PayabliPayInStoredMethodObjC?, NSError?) -> Void
    ) {
        Task { @MainActor in
            defer {
                for digits in request.instrument.sensitiveDigits {
                    digits.close()
                }
            }
            do {
                let method = try await component.storeMethod(request)
                completion(PayabliPayInStoredMethodObjC(method), nil)
            } catch {
                completion(nil, error.toPayabliPayInNSError())
            }
        }
    }

    /// Reads a transaction back by its identifier, as ``PayabliPayIn/readTransaction(_:)`` does.
    ///
    /// - Parameters:
    ///   - transId: the transaction to read.
    ///   - completion: the transaction, or the error the read failed with.
    @objc public func readTransaction(
        transId: String,
        completion: @escaping (PayabliPayInTransactionObjC?, NSError?) -> Void
    ) {
        Task { @MainActor in
            do {
                let transaction = try await component.readTransaction(transId)
                completion(PayabliPayInTransactionObjC(transaction), nil)
            } catch {
                completion(nil, error.toPayabliPayInNSError())
            }
        }
    }

    /// Charges a payment, as ``PayabliPayIn/capture(_:)`` does.
    ///
    /// The error's `userInfo["capture"]` is `1` when the payment may have been taken, including a refusal with code
    /// 1023 because another call for the payment is open and an unknown failure with code 1017, and `0` when it wasn't.
    ///
    /// - Parameter request: the payment and its settings.
    /// - Parameter completion: the result, or the error the charge failed with.
    @objc public func capture(
        _ request: PayabliPayInRequestObjC,
        completion: @escaping (PayabliPayInResultObjC?, NSError?) -> Void
    ) {
        capture(request.toSwift(), completion: completion)
    }

    /// Charges a payment the request carries, closing the request's digit buffers at the task's
    /// end, on a result and a refusal alike: no host can reach them to close them itself.
    ///
    /// - Parameter request: the payment and its settings.
    /// - Parameter completion: the result, or the error the charge failed with.
    func capture(
        _ request: PayabliPayInRequest,
        completion: @escaping (PayabliPayInResultObjC?, NSError?) -> Void
    ) {
        complete(completion) {
            defer {
                for digits in request.paymentMethod.sensitiveDigits {
                    digits.close()
                }
            }
            return try await $0.capture(request)
        }
    }

    /// Holds an amount, as ``PayabliPayIn/authorize(_:)`` does.
    ///
    /// The error's `userInfo["capture"]` reads as it does for ``capture(_:completion:)``.
    ///
    /// - Parameter request: the payment and its settings.
    /// - Parameter completion: the result, or the error the authorization failed with.
    @objc public func authorize(
        _ request: PayabliPayInRequestObjC,
        completion: @escaping (PayabliPayInResultObjC?, NSError?) -> Void
    ) {
        authorize(request.toSwift(), completion: completion)
    }

    /// Holds an amount the request carries, closing the request's digit buffers at the task's end,
    /// on a result and a refusal alike: no host can reach them to close them itself.
    ///
    /// - Parameter request: the payment and its settings.
    /// - Parameter completion: the result, or the error the authorization failed with.
    func authorize(
        _ request: PayabliPayInRequest,
        completion: @escaping (PayabliPayInResultObjC?, NSError?) -> Void
    ) {
        complete(completion) {
            defer {
                for digits in request.paymentMethod.sensitiveDigits {
                    digits.close()
                }
            }
            return try await $0.authorize(request)
        }
    }

    /// Captures an authorization, as ``PayabliPayIn/captureAuthorizedTransaction(_:)`` does.
    ///
    /// The error's `userInfo["capture"]` reads as it does for ``capture(_:completion:)``.
    ///
    /// - Parameter request: the authorization and the amount to capture.
    /// - Parameter completion: the result, or the error the capture failed with.
    @objc public func captureAuthorizedTransaction(
        _ request: PayabliPayInAuthorizedRequestObjC,
        completion: @escaping (PayabliPayInResultObjC?, NSError?) -> Void
    ) {
        let swiftRequest = request.toSwift()
        complete(completion) { try await $0.captureAuthorizedTransaction(swiftRequest) }
    }

    /// Reverses a transaction, as ``PayabliPayIn/voidTransaction(_:)`` does.
    ///
    /// The error's `userInfo["capture"]` reads as it does for ``capture(_:completion:)``.
    ///
    /// - Parameter transId: the transaction to reverse.
    /// - Parameter completion: the result, or the error the reversal failed with.
    @objc public func voidTransaction(
        transId: String,
        completion: @escaping (PayabliPayInResultObjC?, NSError?) -> Void
    ) {
        complete(completion) { try await $0.voidTransaction(transId) }
    }

    private func complete(
        _ completion: @escaping (PayabliPayInResultObjC?, NSError?) -> Void,
        _ operation: @escaping @MainActor (PayabliPayIn) async throws -> PayabliPayInResult
    ) {
        Task { @MainActor in
            do {
                let result = try await operation(component)
                completion(PayabliPayInResultObjC(result), nil)
            } catch {
                completion(nil, error.toPayabliPayInNSError(movesMoney: true))
            }
        }
    }

    /// The bank values in their Swift types, `nil` where the host passed `unspecified`.
    struct BankValues {
        let accountType: PayabliPayInAccountType
        let secCode: PayabliPayInSecCode?
        let holderType: PayabliPayInAccountHolderType?
    }

    /// Reads the bank values an Objective-C host passed. Objective-C passes an enum as a plain integer, so a number
    /// that names no case can arrive, and a switch over it traps.
    ///
    /// - Parameter accountType: the account type the host passed.
    /// - Parameter secCode: the SEC code the host passed.
    /// - Parameter holderType: the holder type the host passed.
    /// - Returns: the values in their Swift types.
    /// - Throws: ``PayabliPayInError/InvalidInput`` naming the request member, for a number that names no case.
    nonisolated static func validated(
        accountType: PayabliPayInAccountTypeCode,
        secCode: PayabliPayInSecCodeCode,
        holderType: PayabliPayInAccountHolderTypeCode
    ) throws -> BankValues {
        guard let account = PayabliPayInAccountTypeCode(rawValue: accountType.rawValue) else {
            throw refusal(accountType.rawValue, of: PayabliPayInAccountTypeCode.self, field: .achAccountType)
        }
        guard let sec = PayabliPayInSecCodeCode(rawValue: secCode.rawValue) else {
            throw refusal(secCode.rawValue, of: PayabliPayInSecCodeCode.self, field: .achCode)
        }
        guard let holder = PayabliPayInAccountHolderTypeCode(rawValue: holderType.rawValue) else {
            throw refusal(holderType.rawValue, of: PayabliPayInAccountHolderTypeCode.self, field: .achHolderType)
        }
        return BankValues(accountType: account.accountType, secCode: sec.secCode, holderType: holder.holderType)
    }

    /// - Parameter value: the number the host passed.
    /// - Parameter type: the enum it names no case of.
    /// - Parameter field: the request member it fills.
    /// - Returns: the refusal, naming that member.
    private nonisolated static func refusal(
        _ value: Int,
        of type: (some Any).Type,
        field: PayabliPayInMethodInput.CodingKeys
    ) -> PayabliPayInError.InvalidInput {
        PayabliPayInError.InvalidInput(field: PayInFieldPath.storedMethod(field), reason: "\(value) is not a \(type) value.")
    }
}

extension Error {
    /// The `NSError` an Objective-C caller receives, adding `field`, `paymentTransId` and `paymentReference` when the
    /// error names them, and an unknown outcome's redacted cause under `NSUnderlyingErrorKey`.
    ///
    /// - Parameter movesMoney: whether the call could take a payment, so the error says whether it may have.
    /// - Returns: the error, with `capture` set to 1 when the payment may have been taken, a refusal because another
    ///   call for the payment is open and an unknown failure included, and 0 when it wasn't.
    func toPayabliPayInNSError(movesMoney: Bool = false) -> NSError {
        let error = payabliNSError(domain: payInObjCErrorDomain)
        var userInfo = error.userInfo
        if let field = (self as? PayabliPayInError.InvalidInput)?.field {
            userInfo["field"] = field as NSString
        }
        let failure = (self as? PayabliPayInError.Refused)?.failure ?? (self as? PayabliPayInError.ServiceError)?.failure
        if let paymentTransId = failure?.paymentTransId {
            userInfo["paymentTransId"] = paymentTransId as NSString
        }
        if let unsettled = self as? PayabliPayInError.Unsettled {
            userInfo["paymentTransId"] = unsettled.paymentTransId
            userInfo["paymentReference"] = unsettled.paymentReference
            userInfo[NSUnderlyingErrorKey] = unsettled.underlying as NSError
            if movesMoney {
                userInfo["capture"] = 1
            }
        } else if movesMoney {
            let type = (self as? any PayabliError)?.type
            let mayHaveBeenTaken = PayInInterruption.isCancellation(self) || type == .paymentReferenceOpen
                || type == .unknown
            userInfo["capture"] = mayHaveBeenTaken ? 1 : 0
        }
        return NSError(domain: error.domain, code: error.code, userInfo: userInfo)
    }
}
