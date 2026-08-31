// PayabliBinding — .NET MAUI / .NET iOS binding for PayabliSDKTapToPay
// and PayabliSDKPayInPaymentFlow.
//
// The C# surface produced by `sharpie bind` against the
// `PayabliSDKTapToPay.xcframework`, `PayabliSDKPayInPaymentFlow.xcframework`,
// and `PayabliSDKCore.xcframework` for `PayabliEnvironment`. Host MAUI apps consume this via a binding
// library project (see `Payabli.MAUI.csproj` next to this file) and
// drive the Tap to Pay on iPhone flow from C#.
//
// All types in this file map 1:1 to the `@objc` companions in
// `Sources/PayabliSDKTapToPay/`. The Swift surface stays untouched;
// the @objc additions added in the same PR make this binding possible
// without a separate shim framework.

using System;
using Foundation;
using ObjCRuntime;

namespace Payabli.TapToPay
{
    // MARK: - PayabliEnvironment (re-declared from PayabliSDKCore)

    [Native]
    public enum PayabliEnvironment : long
    {
        Local = 0,
        QA = 1,
        Sandbox = 2,
        Production = 3,
    }

    // MARK: - PayabliTTPPaymentType

    [Native]
    public enum PayabliTTPPaymentType : long
    {
        Sale = 0,
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
        Error = 8,
    }

    // MARK: - PayabliTTPEventCode

    [Native]
    public enum PayabliTTPEventCode : long
    {
        AttestationStarted = 0,
        AttestationCompleted = 1,
        ConfigReceived = 2,
        ReaderInitializing = 3,
        ReaderReady = 4,
        ChargeInitiated = 5,
        NfcStarted = 6,
        NfcCompleted = 7,
        NfcFailed = 8,
        UpdateCompleted = 9,
        UpdateFailed = 10,
        SessionExpired = 11,
        ReinitializeStarted = 12,
        ReinitializeCompleted = 13,
        DevicePendingActivation = 14,
        ActivationStarted = 15,
        ActivationCompleted = 16,
        ActivationFailed = 17,
        AttestationFailed = 18,
        ConfigFailed = 19,
    }

    // MARK: - Completion delegates

    public delegate void TokenRefreshCompletion(
        [NullAllowed] string token,
        [NullAllowed] NSError error
    );

    public delegate void TokenRefreshRequest(TokenRefreshCompletion completion);

    public delegate void AccessTokenCompletion(
        [NullAllowed] string token,
        [NullAllowed] NSError error
    );

    public delegate void AccessTokenRequest(AccessTokenCompletion completion);

    public delegate void PayabliTTPCompletion([NullAllowed] NSError error);

    public delegate void PayabliTTPChargeCompletion(
        [NullAllowed] PayabliTTPTransactionResultObjC result,
        [NullAllowed] NSError error
    );

    public delegate void PayabliTTPEventHandler(
        PayabliTTPEventCode code,
        NSDictionary payload
    );

    public delegate void PayabliPayInPaymentFlowCompletion(
        [NullAllowed] PayabliPayInPaymentFlowStoredPaymentMethodObjC result,
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

    // MARK: - PayabliTTPTransactionResultObjC (returned by charge completion)

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliTTPTransactionResultObjC
    {
        [Export("paymentTransId")] string PaymentTransId { get; }
    }

    // MARK: - PayabliTTPEventToken (returned by addEventListener)

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliTTPEventToken
    {
        [Export("cancel")] void Cancel();
    }

    // MARK: - PayabliTTP (façade)

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliTTP
    {
        // Convenience init that takes the completion-style token refresh —
        // the @objc-friendly counterpart of the Swift PayabliTokenRefresh
        // closure. Pass null to disable silent refresh (the SDK will
        // surface tokenExpired errors instead).
        // Carries `error:` because the Swift initialiser throws: it rejects an access
        // token that cannot be sent as an HTTP header value, and an empty entry point.
        // The selector must match the generated header exactly or the binding calls
        // one that does not exist.
        [Export("initWithAccessToken:tokenRefreshHandler:entryPoint:appId:environment:error:")]
        IntPtr Constructor(
            string accessToken,
            [NullAllowed] TokenRefreshRequest tokenRefreshHandler,
            string entryPoint,
            string appId,
            PayabliEnvironment environment,
            out NSError error
        );

        // Lifecycle (all @MainActor — completion fires on main thread).

        [Export("initializeWithCompletion:")]
        void Initialize(PayabliTTPCompletion completion);

        [Export("reinitializeIfNeededWithCompletion:")]
        void ReinitializeIfNeeded(PayabliTTPCompletion completion);

        [Export("chargeWithType:paymentDetails:customer:invoice:orderDescription:completion:")]
        void Charge(
            nint type,
            PayabliTTPPaymentDetailsObjC paymentDetails,
            [NullAllowed] PayabliTTPCustomerDataObjC customer,
            [NullAllowed] PayabliTTPInvoiceDataObjC invoice,
            [NullAllowed] string orderDescription,
            PayabliTTPChargeCompletion completion
        );

        [Export("activateDeviceWithActivationCode:completion:")]
        void ActivateDevice(string activationCode, PayabliTTPCompletion completion);

        // Session state (read-only @Published properties).

        [Export("sessionState")] PayabliTTPSessionState SessionState { get; }
        [Export("isReady")] bool IsReady { get; }

        // Event subscription. The returned token's Cancel() tears down the
        // underlying Task so the handler stops receiving events. The handler
        // is always invoked on the main thread.

        [Export("addEventListenerWithHandler:")]
        PayabliTTPEventToken AddEventListener(PayabliTTPEventHandler handler);
    }

    // MARK: - PayIn Payment Flow

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliPayInPaymentFlowStoredPaymentMethodObjC
    {
        [NullAllowed, Export("storedMethodId")] string StoredMethodId { get; }
        [NullAllowed, Export("methodReferenceId")] string MethodReferenceId { get; }
        [NullAllowed, Export("resultCode")] NSNumber ResultCode { get; }
        [NullAllowed, Export("resultText")] string ResultText { get; }
        [NullAllowed, Export("customerId")] NSNumber CustomerId { get; }
        [Export("responseText")] string ResponseText { get; }
        [Export("apiResponse")] NSDictionary ApiResponse { get; }
    }

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliPayInPaymentFlowObjC
    {
        [Export("initWithAccessTokenHandler:entryPoint:environment:")]
        IntPtr Constructor(
            AccessTokenRequest accessTokenHandler,
            string entryPoint,
            PayabliEnvironment environment
        );

        [Export("addCardWithCardNumber:expiration:cardholderName:cvv:billingZip:createAnonymous:forceCustomerCreation:temporary:source:completion:")]
        void AddCard(
            string cardNumber,
            string expiration,
            string cardholderName,
            string cvv,
            string billingZip,
            bool createAnonymous,
            bool forceCustomerCreation,
            bool temporary,
            [NullAllowed] string source,
            PayabliPayInPaymentFlowCompletion completion
        );

        [Export("addACHWithAccountNumber:accountType:holderName:routingNumber:secCode:holderType:achValidation:createAnonymous:forceCustomerCreation:temporary:source:completion:")]
        void AddACH(
            string accountNumber,
            string accountType,
            string holderName,
            string routingNumber,
            [NullAllowed] string secCode,
            [NullAllowed] string holderType,
            bool achValidation,
            bool createAnonymous,
            bool forceCustomerCreation,
            bool temporary,
            [NullAllowed] string source,
            PayabliPayInPaymentFlowCompletion completion
        );
    }
}
