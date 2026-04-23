// PayabliBinding — .NET MAUI / Xamarin.iOS binding skeleton (PRD FR-8).
//
// The C# surface produced by `sharpie bind` against the XCFramework. Host
// apps call `PayabliConfig.Configure` with an access token obtained from
// their own backend (never from a hardcoded clientSecret).
//
// See RFC-0001 §5 Phase 9 and BR-17 for hosting requirements.

using System;
using System.Threading.Tasks;
using Foundation;
using ObjCRuntime;
using UIKit;

namespace Payabli
{
    // Swift async throws -> string becomes a completion with (string?, NSError?).
    public delegate void TokenRefreshCompletion(
        [NullAllowed] string token,
        [NullAllowed] NSError error
    );
    public delegate void TokenRefreshRequest(TokenRefreshCompletion completion);

    [BaseType(typeof(NSObject))]
    public interface PayabliConfig
    {
        [Export("initWithAccessToken:tokenRefresh:entryPoint:environment:telemetryEnabled:")]
        IntPtr Constructor(
            string accessToken,
            [NullAllowed] TokenRefreshRequest tokenRefresh,
            string entryPoint,
            PayabliEnvironment environment,
            bool telemetryEnabled
        );
    }

    [Native]
    public enum PayabliEnvironment : long
    {
        Local = 0,
        QA = 1,
        Sandbox = 2,
        Production = 3,
    }

    [Native]
    public enum PayabliPaymentType : long
    {
        Card = 0,
        ACH = 1,
        ApplePay = 2,
        TapToPay = 3,
    }

    public delegate void PayabliTokenizationCompletion(
        [NullAllowed] string token,
        [NullAllowed] NSError error
    );

    [BaseType(typeof(NSObject))]
    public interface PayabliPayIn
    {
        [Static]
        [Export("shared")]
        PayabliPayIn Shared { get; }

        [Export("configureWithConfig:theme:")]
        void Configure(PayabliConfig config, PayabliTheme theme);

        [Export("createTokenizationViewControllerWithType:customerId:completion:")]
        UIViewController CreateTokenizationViewController(
            PayabliPaymentType type,
            nint customerId,
            PayabliTokenizationCompletion completion
        );
    }

    [BaseType(typeof(NSObject))]
    public interface PayabliTheme
    {
        [Export("initWithPrimaryColorHex:cornerRadius:fontName:")]
        IntPtr Constructor(
            string primaryColorHex,
            nfloat cornerRadius,
            [NullAllowed] string fontName
        );

        [Static, Export("defaultTheme")]
        PayabliTheme Default { get; }
    }
}
