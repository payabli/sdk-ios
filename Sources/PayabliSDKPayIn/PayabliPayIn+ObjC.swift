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

@MainActor
@objc(PayabliPayInObjC)
public final class PayabliPayInObjC: NSObject {
    private let component: PayabliPayIn

    /// Builds the session internally, because an Objective-C caller cannot hold a Swift-only
    /// `PayabliSession`. Throws whatever `PayabliConfig.init` rejects, which is an empty entry point.
    @objc public init(
        tokenHandler: @escaping (@escaping (String?, NSError?) -> Void) -> Void,
        entryPoint: String,
        environment: PayabliEnvironment
    ) throws {
        let tokenProvider = bridgedTokenProvider(errorDomain: payInObjCErrorDomain, tokenHandler)
        let config = try PayabliConfig(
            entryPoint: entryPoint,
            environment: environment,

            tokenProvider: tokenProvider
        )
        component = PayabliPayIn(session: PayabliSession(config: config))
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
        completion: @escaping (PayabliPayInStoredPaymentMethodObjC?, NSError?) -> Void
    ) {
        let card = PayabliPayInCardData(
            cardNumber: cardNumber,
            expiration: expiration,
            cardholderName: cardholderName,
            cvv: cvv,
            billingZip: billingZip
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
            accountNumber: accountNumber,
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

    private func addPaymentMethod(
        _ paymentMethod: PayabliPayInMethodInput,
        options: PayabliPayInOptions,
        completion: @escaping (PayabliPayInStoredPaymentMethodObjC?, NSError?) -> Void
    ) {
        Task { @MainActor in
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

private extension Error {
    func toPayabliPayInNSError() -> NSError {
        if let payInError = self as? any PayabliError {
            return NSError(
                domain: payInObjCErrorDomain,
                code: -3,
                userInfo: [
                    NSLocalizedDescriptionKey: payInError.reason,
                    "PayabliErrorCode": payInError.code.rawValue
                ]
            )
        }
        return self as NSError
    }
}
