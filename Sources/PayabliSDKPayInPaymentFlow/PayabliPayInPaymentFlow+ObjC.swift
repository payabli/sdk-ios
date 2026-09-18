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

    /// Builds the session internally, because an Objective-C caller cannot hold a Swift-only
    /// `PayabliSession`. Throws whatever `PayabliConfig.init` rejects, which is an empty entry point.
    @objc public init(
        tokenHandler: @escaping (@escaping (String?, NSError?) -> Void) -> Void,
        entryPoint: String,
        environment: PayabliEnvironment
    ) throws {
        let tokenProvider = bridgedTokenProvider(errorDomain: "com.payabli.payInPaymentFlow", tokenHandler)
        let config = try PayabliConfig(
            entryPoint: entryPoint,
            environment: environment,

            tokenProvider: tokenProvider
        )
        component = PayabliPayInPaymentFlow(session: PayabliSession(config: config))
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
