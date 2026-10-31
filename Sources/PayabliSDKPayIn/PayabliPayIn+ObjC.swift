import Foundation
import PayabliSDKCore

/// The `NSError` domain every error this facade hands to an ObjC caller carries, whatever it wraps.
private let payInObjCErrorDomain = "com.payabli.payIn"

@objc(PayabliPayInStoredPaymentMethodObjC)
public final class PayabliPayInStoredPaymentMethodObjC: NSObject {
    @objc public let storedMethodId: String?
    @objc public let method: String
    @objc public let methodReferenceId: String?
    @objc public let resultCode: NSNumber?
    @objc public let resultText: String?
    @objc public let customerId: NSNumber?
    @objc public let responseText: String
    @objc public let apiResponse: NSDictionary

    init(_ method: PayabliPayInStoredPaymentMethod) {
        storedMethodId = method.storedMethodId
        self.method = Self.name(of: method.method)
        methodReferenceId = method.methodReferenceId
        resultCode = method.resultCode.map(NSNumber.init(value:))
        resultText = method.resultText
        customerId = method.customerId.map(NSNumber.init(value:))
        responseText = method.responseText
        apiResponse = Self.dictionary(from: method.apiResponse)
        super.init()
    }

    private static func name(of method: PayabliPayInStoredMethodType) -> String {
        switch method {
        case .card: return "card"
        case .bankAccount: return "bankAccount"
        }
    }

    private static func dictionary(from response: PayabliPayInTokenStorageAPIResponse) -> NSDictionary {
        guard let data = try? JSONEncoder().encode(response),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object as NSDictionary
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

    // swiftlint:disable:next function_parameter_count
    @objc public func addCard(
        cardNumber: String,
        expiry: String,
        holderName: String,
        securityCode: String,
        postalCode: String,
        createAnonymous: Bool,
        forceCustomerCreation: Bool,
        temporary: Bool,
        source: String?,
        completion: @escaping (PayabliPayInStoredPaymentMethodObjC?, NSError?) -> Void
    ) {
        let card = PayabliPayInCardData(
            cardNumber: SensitiveDigits.ofString(cardNumber),
            expiry: expiry,
            holderName: holderName,
            securityCode: SensitiveDigits.ofString(securityCode),
            postalCode: postalCode
        )
        let options = PayabliPayInOptions(
            createAnonymous: createAnonymous,
            forceCustomerCreation: forceCustomerCreation,
            temporary: temporary,
            source: source
        )
        addPaymentMethod(.card(card), options: options, completion: completion)
    }

    // swiftlint:disable:next function_parameter_count
    @objc public func addBankAccount(
        accountNumber: String,
        accountType: String,
        holderName: String,
        routingNumber: String,
        secCode: String?,
        holderType: String?,
        achValidation: Bool,
        createAnonymous: Bool,
        forceCustomerCreation: Bool,
        temporary: Bool,
        source: String?,
        completion: @escaping (PayabliPayInStoredPaymentMethodObjC?, NSError?) -> Void
    ) {
        guard let resolvedAccountType = PayabliPayInAccountType(rawValue: accountType) else {
            completion(nil, invalidArgument("accountType must be Checking or Savings"))
            return
        }
        let resolvedSecCode: PayabliPayInSecCode
        if let secCode {
            guard let secCode = PayabliPayInSecCode(rawValue: secCode) else {
                completion(nil, invalidArgument("secCode must be PPD, WEB, TEL, CCD, or BOC"))
                return
            }
            resolvedSecCode = secCode
        } else {
            resolvedSecCode = .web
        }
        let resolvedHolderType: PayabliPayInAccountHolderType?
        if let holderType {
            guard let holderType = PayabliPayInAccountHolderType(rawValue: holderType) else {
                completion(nil, invalidArgument("holderType must be personal or business"))
                return
            }
            resolvedHolderType = holderType
        } else {
            resolvedHolderType = nil
        }

        let ach = PayabliPayInBankAccountData(
            accountNumber: SensitiveDigits.ofString(accountNumber),
            accountType: resolvedAccountType,
            holderName: holderName,
            routingNumber: routingNumber,
            secCode: resolvedSecCode,
            holderType: resolvedHolderType
        )
        let options = PayabliPayInOptions(
            achValidation: achValidation,
            createAnonymous: createAnonymous,
            forceCustomerCreation: forceCustomerCreation,
            temporary: temporary,
            source: source
        )
        addPaymentMethod(.bankAccount(ach), options: options, completion: completion)
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
    /// 1023 because another call for the payment is open, and `0` when it wasn't.
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
            // Both exits: a result and a refusal have both finished with the digits.
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
            // Both exits: a result and a refusal have both finished with the digits.
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

    /// Stores a payment method the adapter built from strings, closing the buffers it built for
    /// them at the task's end: a host cannot reach those buffers to close them itself.
    ///
    /// - Parameter paymentMethod: the method to store.
    /// - Parameter options: what the request carries besides the method.
    /// - Parameter completion: the stored method, or the error the store failed with.
    func addPaymentMethod(
        _ paymentMethod: PayabliPayInMethodInput,
        options: PayabliPayInOptions,
        completion: @escaping (PayabliPayInStoredPaymentMethodObjC?, NSError?) -> Void
    ) {
        Task { @MainActor in
            // Both exits: a stored method and a refusal have both finished with the digits.
            defer {
                for digits in paymentMethod.sensitiveDigits {
                    digits.close()
                }
            }
            do {
                let result = try await component.addPaymentMethod(
                    paymentMethod,
                    options: options
                )
                completion(PayabliPayInStoredPaymentMethodObjC(result), nil)
            } catch {
                completion(nil, error.toPayabliPayInNSError())
            }
        }
    }

    private func invalidArgument(_ message: String) -> NSError {
        NSError(
            domain: payInObjCErrorDomain,
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

extension Error {
    /// The `NSError` an Objective-C caller receives; an unknown outcome adds `paymentTransId` and `paymentReference`.
    ///
    /// - Parameter movesMoney: whether the call could take a payment, so the error says whether it may have.
    /// - Returns: the error, with `capture` set to 1 when the payment may have been taken, a refusal because another
    ///   call for the payment is open included, and 0 when it wasn't.
    func toPayabliPayInNSError(movesMoney: Bool = false) -> NSError {
        let error = payabliNSError(domain: payInObjCErrorDomain)
        var userInfo = error.userInfo
        if case let .submissionInterrupted(_, _, paymentTransId, paymentReference) = self as? PayabliPayInError {
            userInfo["paymentTransId"] = paymentTransId
            userInfo["paymentReference"] = paymentReference
            if movesMoney {
                userInfo["capture"] = 1
            }
        } else if movesMoney {
            let paymentIsOpen = (self as? any PayabliError)?.type == .paymentReferenceOpen
            userInfo["capture"] = PayInInterruption.isCancellation(self) || paymentIsOpen ? 1 : 0
        }
        return NSError(domain: error.domain, code: error.code, userInfo: userInfo)
    }
}

private extension PayabliPayInMethodInput {
    /// The buffers this facade's input holds, listed where the task that spends them closes them:
    /// the adapter builds them from strings, so no host can reach them to close them itself.
    var sensitiveDigits: [SensitiveDigits] {
        switch self {
        case let .card(data): [data.cardNumber, data.securityCode]
        case let .bankAccount(data): [data.accountNumber]
        }
    }
}
