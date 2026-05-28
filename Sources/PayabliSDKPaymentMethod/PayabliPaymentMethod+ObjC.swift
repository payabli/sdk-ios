import Foundation
import PayabliSDKCore

@objc(PayabliStoredPaymentMethodObjC)
public final class PayabliStoredPaymentMethodObjC: NSObject {
    @objc public let storedMethodId: String?
    @objc public let methodReferenceId: String?
    @objc public let resultCode: NSNumber?
    @objc public let resultText: String?
    @objc public let customerId: NSNumber?
    @objc public let responseText: String
    @objc public let apiResponse: NSDictionary

    init(_ method: PayabliStoredPaymentMethod) {
        storedMethodId = method.storedMethodId
        methodReferenceId = method.methodReferenceId
        resultCode = method.resultCode.map(NSNumber.init(value:))
        resultText = method.resultText
        customerId = method.customerId.map(NSNumber.init(value:))
        responseText = method.responseText
        apiResponse = Self.dictionary(from: method.apiResponse)
        super.init()
    }

    private static func dictionary(from response: PayabliPaymentMethodAPIResponse) -> NSDictionary {
        guard let data = try? JSONEncoder().encode(response),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object as NSDictionary
    }
}

@MainActor
@objc(PayabliPaymentMethodObjC)
public final class PayabliPaymentMethodObjC: NSObject {
    private let component: PayabliPaymentMethod

    @objc public init(
        accessTokenHandler: @escaping (@escaping (String?, NSError?) -> Void) -> Void,
        entryPoint: String,
        environment: PayabliEnvironment
    ) {
        let sendable = UncheckedSendableBox(accessTokenHandler)
        let accessTokenProvider: PayabliPaymentMethodAccessTokenProvider = {
            try await withCheckedThrowingContinuation { continuation in
                let resumed = Locked(false)
                sendable.value { token, error in
                    let firstCall = resumed.withLock { hasResumed in
                        guard !hasResumed else { return false }
                        hasResumed = true
                        return true
                    }
                    guard firstCall else { return }
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let token {
                        continuation.resume(returning: token)
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "com.payabli.paymentMethod",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey:
                                "accessTokenHandler returned nil token and nil error"]
                        ))
                    }
                }
            }
        }
        component = PayabliPaymentMethod(
            entryPoint: entryPoint,
            environment: environment,
            accessTokenProvider: accessTokenProvider
        )
        super.init()
    }

    // swiftlint:disable:next function_parameter_count
    @objc public func addCard(
        cardNumber: String,
        expiration: String,
        cardholderName: String,
        cvv: String?,
        billingZip: String,
        createAnonymous: Bool,
        forceCustomerCreation: Bool,
        temporary: Bool,
        source: String?,
        completion: @escaping (PayabliStoredPaymentMethodObjC?, NSError?) -> Void
    ) {
        let card = PayabliCardPaymentMethodData(
            cardNumber: cardNumber,
            expiration: expiration,
            cardholderName: cardholderName,
            cvv: cvv,
            billingZip: billingZip
        )
        let options = PayabliPaymentMethodOptions(
            createAnonymous: createAnonymous,
            forceCustomerCreation: forceCustomerCreation,
            temporary: temporary,
            source: source
        )
        addPaymentMethod(.card(card), options: options, completion: completion)
    }

    // swiftlint:disable:next function_parameter_count
    @objc public func addACH(
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
        completion: @escaping (PayabliStoredPaymentMethodObjC?, NSError?) -> Void
    ) {
        guard let resolvedAccountType = PayabliACHAccountType(rawValue: accountType) else {
            completion(nil, invalidArgument("accountType must be Checking or Savings"))
            return
        }
        let resolvedSecCode: PayabliACHSecCode
        if let secCode {
            guard let secCode = PayabliACHSecCode(rawValue: secCode) else {
                completion(nil, invalidArgument("secCode must be PPD, WEB, TEL, CCD, or BOC"))
                return
            }
            resolvedSecCode = secCode
        } else {
            resolvedSecCode = .web
        }

        let ach = PayabliACHPaymentMethodData(
            accountNumber: accountNumber,
            accountType: resolvedAccountType,
            holderName: holderName,
            routingNumber: routingNumber,
            secCode: resolvedSecCode,
            holderType: holderType.flatMap(PayabliACHHolderType.init(rawValue:))
        )
        let options = PayabliPaymentMethodOptions(
            achValidation: achValidation,
            createAnonymous: createAnonymous,
            forceCustomerCreation: forceCustomerCreation,
            temporary: temporary,
            source: source
        )
        addPaymentMethod(.ach(ach), options: options, completion: completion)
    }

    private func addPaymentMethod(
        _ paymentMethod: PayabliPaymentMethodInput,
        options: PayabliPaymentMethodOptions,
        completion: @escaping (PayabliStoredPaymentMethodObjC?, NSError?) -> Void
    ) {
        Task { @MainActor in
            do {
                let result = try await component.addPaymentMethod(
                    paymentMethod,
                    options: options
                )
                completion(PayabliStoredPaymentMethodObjC(result), nil)
            } catch {
                completion(nil, error.toPayabliPaymentMethodNSError())
            }
        }
    }

    private func invalidArgument(_ message: String) -> NSError {
        NSError(
            domain: "com.payabli.paymentMethod",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) {
        self.value = value
    }
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

private extension Error {
    func toPayabliPaymentMethodNSError() -> NSError {
        if let paymentMethodError = self as? PayabliPaymentMethodError {
            return NSError(
                domain: "com.payabli.paymentMethod",
                code: -3,
                userInfo: [
                    NSLocalizedDescriptionKey: paymentMethodError.reason,
                    "PayabliErrorCode": paymentMethodError.code.rawValue
                ]
            )
        }
        return self as NSError
    }
}
