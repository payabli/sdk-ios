import Foundation
import PayabliSDKCore

@objc(PayabliPayInPaymentFlowStoredPaymentMethodObjC)
public final class PayabliPayInPaymentFlowStoredPaymentMethodObjC: NSObject {
    @objc public let storedMethodId: String?
    @objc public let methodReferenceId: String?
    @objc public let resultCode: NSNumber?
    @objc public let resultText: String?
    @objc public let customerId: NSNumber?
    @objc public let responseText: String
    @objc public let apiResponse: NSDictionary

    init(_ method: PayabliPayInPaymentFlowStoredPaymentMethod) {
        storedMethodId = method.storedMethodId
        methodReferenceId = method.methodReferenceId
        resultCode = method.resultCode.map(NSNumber.init(value:))
        resultText = method.resultText
        customerId = method.customerId.map(NSNumber.init(value:))
        responseText = method.responseText
        apiResponse = Self.dictionary(from: method.apiResponse)
        super.init()
    }

    private static func dictionary(from response: PayabliPayInPaymentFlowTokenStorageAPIResponse) -> NSDictionary {
        guard let data = try? JSONEncoder().encode(response),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object as NSDictionary
    }
}

@MainActor
@objc(PayabliPayInPaymentFlowObjC)
public final class PayabliPayInPaymentFlowObjC: NSObject {
    private let component: PayabliPayInPaymentFlow

    @objc public init(
        accessTokenHandler: @escaping (@escaping (String?, NSError?) -> Void) -> Void,
        entryPoint: String,
        environment: PayabliEnvironment
    ) {
        let sendable = UncheckedSendableBox(accessTokenHandler)
        let accessTokenProvider: PayabliPayInPaymentFlowAccessTokenProvider = {
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
                            domain: "com.payabli.payInPaymentFlow",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey:
                                "accessTokenHandler returned nil token and nil error"]
                        ))
                    }
                }
            }
        }
        component = PayabliPayInPaymentFlow(
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
        cvv: String,
        billingZip: String,
        createAnonymous: Bool,
        forceCustomerCreation: Bool,
        temporary: Bool,
        source: String?,
        completion: @escaping (PayabliPayInPaymentFlowStoredPaymentMethodObjC?, NSError?) -> Void
    ) {
        let card = PayabliPayInPaymentFlowCardData(
            cardNumber: cardNumber,
            expiration: expiration,
            cardholderName: cardholderName,
            cvv: cvv,
            billingZip: billingZip
        )
        let options = PayabliPayInPaymentFlowOptions(
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
        completion: @escaping (PayabliPayInPaymentFlowStoredPaymentMethodObjC?, NSError?) -> Void
    ) {
        guard let resolvedAccountType = PayabliPayInPaymentFlowACHAccountType(rawValue: accountType) else {
            completion(nil, invalidArgument("accountType must be Checking or Savings"))
            return
        }
        let resolvedSecCode: PayabliPayInPaymentFlowACHSecCode
        if let secCode {
            guard let secCode = PayabliPayInPaymentFlowACHSecCode(rawValue: secCode) else {
                completion(nil, invalidArgument("secCode must be PPD, WEB, TEL, CCD, or BOC"))
                return
            }
            resolvedSecCode = secCode
        } else {
            resolvedSecCode = .web
        }
        let resolvedHolderType: PayabliPayInPaymentFlowACHHolderType?
        if let holderType {
            guard let holderType = PayabliPayInPaymentFlowACHHolderType(rawValue: holderType) else {
                completion(nil, invalidArgument("holderType must be personal or business"))
                return
            }
            resolvedHolderType = holderType
        } else {
            resolvedHolderType = nil
        }

        let ach = PayabliPayInPaymentFlowACHData(
            accountNumber: accountNumber,
            accountType: resolvedAccountType,
            holderName: holderName,
            routingNumber: routingNumber,
            secCode: resolvedSecCode,
            holderType: resolvedHolderType
        )
        let options = PayabliPayInPaymentFlowOptions(
            achValidation: achValidation,
            createAnonymous: createAnonymous,
            forceCustomerCreation: forceCustomerCreation,
            temporary: temporary,
            source: source
        )
        addPaymentMethod(.ach(ach), options: options, completion: completion)
    }

    private func addPaymentMethod(
        _ paymentMethod: PayabliPayInPaymentFlowMethodInput,
        options: PayabliPayInPaymentFlowOptions,
        completion: @escaping (PayabliPayInPaymentFlowStoredPaymentMethodObjC?, NSError?) -> Void
    ) {
        Task { @MainActor in
            do {
                let result = try await component.addPaymentMethod(
                    paymentMethod,
                    options: options
                )
                completion(PayabliPayInPaymentFlowStoredPaymentMethodObjC(result), nil)
            } catch {
                completion(nil, error.toPayabliPayInPaymentFlowNSError())
            }
        }
    }

    private func invalidArgument(_ message: String) -> NSError {
        NSError(
            domain: "com.payabli.payInPaymentFlow",
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
    func toPayabliPayInPaymentFlowNSError() -> NSError {
        if let payInPaymentFlowError = self as? any PayabliError {
            return NSError(
                domain: "com.payabli.payInPaymentFlow",
                code: -3,
                userInfo: [
                    NSLocalizedDescriptionKey: payInPaymentFlowError.reason,
                    "PayabliErrorCode": payInPaymentFlowError.code.rawValue
                ]
            )
        }
        return self as NSError
    }
}
