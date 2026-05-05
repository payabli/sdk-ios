// PayabliBinding — .NET MAUI / Xamarin.iOS binding for PayabliSDKTapToPay.
//
// The C# surface produced by `sharpie bind` against the
// `PayabliSDKTapToPay.xcframework` (and `PayabliSDKCore.xcframework` for
// `PayabliEnvironment`). Host MAUI apps consume this via a binding
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
    }

    // MARK: - Completion delegates

    public delegate void TokenRefreshCompletion(
        [NullAllowed] string token,
        [NullAllowed] NSError error
    );

    public delegate void TokenRefreshRequest(TokenRefreshCompletion completion);

    public delegate void PayabliTTPCompletion([NullAllowed] NSError error);

    public delegate void PayabliTTPChargeCompletion(
        [NullAllowed] PayabliTTPTransactionResultObjC result,
        [NullAllowed] NSError error
    );

    public delegate void PayabliTTPEventHandler(
        PayabliTTPEventCode code,
        NSDictionary payload
    );

    // MARK: - PayabliTTPCustomerDataObjC

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliTTPCustomerDataObjC
    {
        [Export("initWithFirstName:lastName:customerNumber:email:phone:")]
        IntPtr Constructor(
            [NullAllowed] string firstName,
            [NullAllowed] string lastName,
            [NullAllowed] string customerNumber,
            [NullAllowed] string email,
            [NullAllowed] string phone
        );

        [NullAllowed, Export("firstName")] string FirstName { get; }
        [NullAllowed, Export("lastName")] string LastName { get; }
        [NullAllowed, Export("customerNumber")] string CustomerNumber { get; }
        [NullAllowed, Export("email")] string Email { get; }
        [NullAllowed, Export("phone")] string Phone { get; }
    }

    // MARK: - PayabliTTPOrderDataObjC

    [BaseType(typeof(NSObject))]
    [DisableDefaultCtor]
    public interface PayabliTTPOrderDataObjC
    {
        [Export("initWithOrderId:orderDescription:invoiceNumber:")]
        IntPtr Constructor(
            [NullAllowed] string orderId,
            [NullAllowed] string orderDescription,
            [NullAllowed] string invoiceNumber
        );

        [NullAllowed, Export("orderId")] string OrderId { get; }
        [NullAllowed, Export("orderDescription")] string OrderDescription { get; }
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
        [Export("initWithAccessToken:tokenRefreshHandler:entryPoint:appId:environment:")]
        IntPtr Constructor(
            string accessToken,
            [NullAllowed] TokenRefreshRequest tokenRefreshHandler,
            string entryPoint,
            string appId,
            PayabliEnvironment environment
        );

        // Lifecycle (all @MainActor — completion fires on main thread).

        [Export("initializeWithCompletion:")]
        void Initialize(PayabliTTPCompletion completion);

        [Export("reinitializeIfNeededWithCompletion:")]
        void ReinitializeIfNeeded(PayabliTTPCompletion completion);

        [Export("chargeWithAmount:type:serviceFee:customer:order:completion:")]
        void Charge(
            NSDecimalNumber amount,
            nint type,
            NSDecimalNumber serviceFee,
            [NullAllowed] PayabliTTPCustomerDataObjC customer,
            [NullAllowed] PayabliTTPOrderDataObjC order,
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
}
