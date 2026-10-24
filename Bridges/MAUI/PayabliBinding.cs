// PayabliBinding — .NET MAUI / .NET iOS binding for PayabliSDKTapToPay
// and PayabliSDKPayIn.
//
// The C# surface produced by `sharpie bind` against the
// `PayabliSDKTapToPay.xcframework`, `PayabliSDKPayIn.xcframework`,
// with `PayabliSDKCore.xcframework` and `PayabliSDKTelemetry.xcframework`, which both load. Host MAUI apps consume this via a binding
// library project (see `Payabli.MAUI.csproj` next to this file) and
// drive the Tap to Pay on iPhone flow from C#.
//
// All types in this file map 1:1 to the `@objc` companions in
// `Sources/PayabliSDKCore/`, `Sources/PayabliSDKTapToPay/` and `Sources/PayabliSDKPayIn/`. The Swift surface stays untouched;
// the @objc additions added in the same PR make this binding possible
// without a separate shim framework.

using System;
using Foundation;
using ObjCRuntime;

namespace Payabli.TapToPay
{
    // MARK: - PayabliEnvironment (the closed set the SDK offers)

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliEnvironment
    {
        // The two environments the SDK commits, exposed as class properties on
        // the native side; nothing constructs one.
        [Static]
        [Export("sandbox")]
        PayabliEnvironment Sandbox { get; }

        [Static]
        [Export("production")]
        PayabliEnvironment Production { get; }
    }

    // MARK: - PayabliTTPSessionState

    [Native]
    public enum PayabliTTPSessionState : long
    {
        Idle = 0,
        AttestingDevice = 1,
        FetchingConfig = 2,
        InitializingReader = 3,
        Ready = 4,
        SessionExpired = 5,
        Reinitializing = 6,
        PendingActivation = 7,
        Failed = 8,
        PendingTerms = 9,
        Charging = 10,
    }

    // MARK: - Completion delegates

    public delegate void TokenRefreshCompletion(
        [NullAllowed] string token,
        [NullAllowed] NSError error
    );

    public delegate void TokenRefreshRequest(TokenRefreshCompletion completion);

    public delegate void PayabliSessionCompletion([NullAllowed] NSError error);

    public delegate void PayabliTTPCompletion([NullAllowed] NSError error);

    public delegate void PayabliTTPCreateCompletion([NullAllowed] PayabliTTP ttp, [NullAllowed] NSError error);

    public delegate void PayabliTTPChargeCompletion(
        [NullAllowed] PayabliTTPTransactionResultObjC result,
        [NullAllowed] NSError error
    );

    // `accepted` is false on the failure path as a bridging default and is not an
    // answer. Read `error` first: it separates "the merchant has not accepted"
    // from "the reader could not answer", which covers no reader and a platform
    // that raised.
    public delegate void PayabliTTPTermsCompletion(
        bool accepted,
        [NullAllowed] NSError error
    );

    public delegate void TapToPaySessionStateHandler();

    public delegate void PayabliPayInCompletion(
        [NullAllowed] PayabliPayInStoredMethodObjC result,
        [NullAllowed] NSError error
    );

    // MARK: - PayabliTTPCustomerDataObjC

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliTTPCustomerDataObjC
    {
        [Export("initWithFirstName:lastName:customerNumber:email:phone:customerId:company:billingAddress1:billingAddress2:billingCity:billingState:billingZip:billingCountry:billingPhone:billingEmail:shippingAddress1:shippingAddress2:shippingCity:shippingState:shippingZip:shippingCountry:")]
        IntPtr Constructor(
            [NullAllowed] string firstName,
            [NullAllowed] string lastName,
            [NullAllowed] string customerNumber,
            [NullAllowed] string email,
            [NullAllowed] string phone,
            [NullAllowed] NSNumber customerId,
            [NullAllowed] string company,
            [NullAllowed] string billingAddress1,
            [NullAllowed] string billingAddress2,
            [NullAllowed] string billingCity,
            [NullAllowed] string billingState,
            [NullAllowed] string billingZip,
            [NullAllowed] string billingCountry,
            [NullAllowed] string billingPhone,
            [NullAllowed] string billingEmail,
            [NullAllowed] string shippingAddress1,
            [NullAllowed] string shippingAddress2,
            [NullAllowed] string shippingCity,
            [NullAllowed] string shippingState,
            [NullAllowed] string shippingZip,
            [NullAllowed] string shippingCountry
        );

        [NullAllowed, Export("firstName")] string FirstName { get; }
        [NullAllowed, Export("lastName")] string LastName { get; }
        [NullAllowed, Export("customerNumber")] string CustomerNumber { get; }
        [NullAllowed, Export("email")] string Email { get; }
        [NullAllowed, Export("phone")] string Phone { get; }
        [NullAllowed, Export("customerId")] NSNumber CustomerId { get; }
        [NullAllowed, Export("company")] string Company { get; }
        [NullAllowed, Export("billingAddress1")] string BillingAddress1 { get; }
        [NullAllowed, Export("billingAddress2")] string BillingAddress2 { get; }
        [NullAllowed, Export("billingCity")] string BillingCity { get; }
        [NullAllowed, Export("billingState")] string BillingState { get; }
        [NullAllowed, Export("billingZip")] string BillingZip { get; }
        [NullAllowed, Export("billingCountry")] string BillingCountry { get; }
        [NullAllowed, Export("billingPhone")] string BillingPhone { get; }
        [NullAllowed, Export("billingEmail")] string BillingEmail { get; }
        [NullAllowed, Export("shippingAddress1")] string ShippingAddress1 { get; }
        [NullAllowed, Export("shippingAddress2")] string ShippingAddress2 { get; }
        [NullAllowed, Export("shippingCity")] string ShippingCity { get; }
        [NullAllowed, Export("shippingState")] string ShippingState { get; }
        [NullAllowed, Export("shippingZip")] string ShippingZip { get; }
        [NullAllowed, Export("shippingCountry")] string ShippingCountry { get; }
    }

    // MARK: - PayabliTTPPaymentDetailsObjC

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliTTPPaymentDetailsObjC
    {
        [Export("initWithAmount:serviceFee:currency:paymentDescription:")]
        IntPtr Constructor(
            NSDecimalNumber amount,
            NSDecimalNumber serviceFee,
            string currency,
            [NullAllowed] string paymentDescription
        );

        [Export("amount")] NSDecimalNumber Amount { get; }
        [Export("serviceFee")] NSDecimalNumber ServiceFee { get; }
        [Export("currency")] string Currency { get; }
        [NullAllowed, Export("paymentDescription")] string PaymentDescription { get; }
    }

    // MARK: - PayabliTTPInvoiceDataObjC

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliTTPInvoiceDataObjC
    {
        [Export("initWithInvoiceNumber:")]
        IntPtr Constructor([NullAllowed] string invoiceNumber);

        [NullAllowed, Export("invoiceNumber")] string InvoiceNumber { get; }
    }

    // MARK: - PayabliTTPChargeRequestObjC

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliTTPChargeRequestObjC
    {
        [Export("initWithPaymentDetails:")]
        IntPtr Constructor(PayabliTTPPaymentDetailsObjC paymentDetails);

        [Export("paymentDetails")] PayabliTTPPaymentDetailsObjC PaymentDetails { get; }
        [NullAllowed, Export("customer", ArgumentSemantic.Strong)] PayabliTTPCustomerDataObjC Customer { get; set; }
        [NullAllowed, Export("invoice", ArgumentSemantic.Strong)] PayabliTTPInvoiceDataObjC Invoice { get; set; }
        [NullAllowed, Export("orderDescription")] string OrderDescription { get; set; }
    }

    // MARK: - PayabliTTPTransactionResultObjC (returned by charge completion)

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliTTPTransactionResultObjC
    {
        [Export("paymentTransId")] string PaymentTransId { get; }
    }

    // MARK: - TapToPaySessionStateObservation (returned by addSessionStateObserver)

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface TapToPaySessionStateObservation
    {
        [Export("cancel")] void Cancel();
    }

    // MARK: - PayabliSessionObjC (the one session)

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliSessionObjC
    {
        // Installs the one session every facade runs on. The token handler is the only source of a
        // credential: the SDK asks it for the first token as well as for a replacement. A second
        // call with the same entry point and environment is a no-op; a different one fails with the
        // error the completion receives.
        [Static]
        [Export("initializeWithTokenHandler:entryPoint:environment:completionHandler:")]
        void Initialize(
            TokenRefreshRequest tokenHandler,
            string entryPoint,
            PayabliEnvironment environment,
            PayabliSessionCompletion completionHandler
        );

        // This device's identity, null before Initialize and while the device's secure storage
        // cannot be read.
        [Static, NullAllowed]
        [Export("deviceId")]
        string DeviceId { get; }
    }

    // MARK: - PayabliTTP (façade)

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliTTP
    {
        // Runs on the session PayabliSessionObjC.Initialize installed. The completion receives
        // an error instead of a facade when no session is installed.
        [Static]
        [Export("createWithCompletionHandler:")]
        void Create(PayabliTTPCreateCompletion completionHandler);

        // Lifecycle (all @MainActor — completion fires on main thread).

        [Export("initializeWithCompletion:")]
        void Initialize(PayabliTTPCompletion completion);

        [Export("charge:completion:")]
        void Charge(PayabliTTPChargeRequestObjC request, PayabliTTPChargeCompletion completion);

        [Export("activateDeviceWithActivationCode:completion:")]
        void ActivateDevice(string activationCode, PayabliTTPCompletion completion);

        [Export("areTermsAcceptedWithCompletion:")]
        void AreTermsAccepted(PayabliTTPTermsCompletion completion);

        [Export("presentTermsWithCompletion:")]
        void PresentTerms(PayabliTTPCompletion completion);

        // Session state (read-only @Published properties).

        // The Swift state carries payloads and is not Objective-C representable,
        // so a host reads the code and then asks for what it carries.
        [Export("sessionStateCode")] PayabliTTPSessionState SessionState { get; }

        [NullAllowed, Export("readerConfigurationPercent")] NSNumber ReaderConfigurationPercent { get; }

        [NullAllowed, Export("failureReason")] NSNumber FailureReason { get; }

        // A TapToPayChargeActivity raw value, null when no charge runs.
        [NullAllowed, Export("chargeActivity")] NSNumber ChargeActivity { get; }

        [NullAllowed, Export("activationId")] string ActivationId { get; }
        [Export("isReady")] bool IsReady { get; }

        // Called on the main thread after every session state change; read the state from this
        // facade. Cancel() on the returned observation stops the calls.
        [Export("addSessionStateObserver:")]
        TapToPaySessionStateObservation AddSessionStateObserver(TapToPaySessionStateHandler handler);
    }

    // MARK: - PayIn Payment Flow

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliPayInStoredMethodObjC
    {
        [NullAllowed, Export("storedMethodId")] string StoredMethodId { get; }
        [Export("method")] string Method { get; }
        [NullAllowed, Export("methodReferenceId")] string MethodReferenceId { get; }
        [NullAllowed, Export("resultCode")] NSNumber ResultCode { get; }
        [NullAllowed, Export("resultText")] string ResultText { get; }
        [NullAllowed, Export("customerId")] NSNumber CustomerId { get; }
        [Export("responseText")] string ResponseText { get; }
        [Export("apiResponse")] NSDictionary ApiResponse { get; }
    }

    // A store request comes from a factory naming its kind, and the option
    // properties are set on it afterwards; what is left null the paypoint's own
    // settings decide.
    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliPayInStoreRequestObjC
    {
        [Static]
        [Export("cardWithCardNumber:expiration:cardholderName:cvv:billingZip:")]
        PayabliPayInStoreRequestObjC Card(
            string cardNumber,
            string expiration,
            string cardholderName,
            string cvv,
            string billingZip
        );

        // Null when a named value names none of the kinds the request takes.
        [Static]
        [return: NullAllowed]
        [Export("bankAccountWithAccountNumber:accountType:holderName:routingNumber:secCode:holderType:")]
        PayabliPayInStoreRequestObjC BankAccount(
            string accountNumber,
            string accountType,
            string holderName,
            string routingNumber,
            [NullAllowed] string secCode,
            [NullAllowed] string holderType
        );

        [NullAllowed, Export("achValidation")] NSNumber AchValidation { get; set; }
        [NullAllowed, Export("createAnonymous")] NSNumber CreateAnonymous { get; set; }
        [NullAllowed, Export("forceCustomerCreation")] NSNumber ForceCustomerCreation { get; set; }
        [NullAllowed, Export("temporary")] NSNumber Temporary { get; set; }
        [NullAllowed, Export("source")] string Source { get; set; }
    }

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliPayInObjC
    {
        // Builds the facade on the installed session, and fails with `error` when none is installed.
        [Static]
        [Export("createAndReturnError:")]
        [return: NullAllowed]
        PayabliPayInObjC Create(out NSError error);

        // Stores the payment method the request names, with the options set on it.
        [Export("storeMethodWithRequest:completion:")]
        void StoreMethod(
            PayabliPayInStoreRequestObjC request,
            PayabliPayInCompletion completion
        );
    }
}
