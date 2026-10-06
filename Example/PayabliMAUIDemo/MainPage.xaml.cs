using Foundation;
using Payabli.TapToPay;

namespace PayabliMauiDemo;

/// <summary>
/// MAUI demo page exercising the full PayabliTTP API surface end-to-end:
///   - Initialize() — cold/warm App Attest + reader prepare.
///   - Charge(amount) — full sale pipeline (initiate → NFC tap → update).
///   - ActivateDevice(code) — pending-device activation.
///   - addEventListener — live lifecycle event log.
/// </summary>
public partial class MainPage : ContentPage
{
    private PayabliTTP? _ttp;
    private PayabliPayInObjC? _payIn;
    private PayabliTTPEventToken? _eventToken;
    private bool _isWorking;
    private bool _isSubmittingPayIn;

    public MainPage()
    {
        InitializeComponent();
        ConfigurePayabli();
    }

    /// <summary>
    /// Starts the one session, then builds both facades on it. The token handler is the only source
    /// of a credential: the SDK asks it for the first token as well as for a replacement, so the app
    /// holds none. Wire it to your own /payabli/token endpoint, and never embed the clientSecret
    /// in the mobile binary.
    /// </summary>
    private void ConfigurePayabli()
    {
        PayabliSessionObjC.Initialize(
            tokenHandler: (completion) =>
            {
                Task.Run(async () =>
                {
                    try
                    {
                        var fresh = await FetchAccessTokenFromPartnerBackend();
                        completion(fresh, null);
                    }
                    catch (System.Exception ex)
                    {
                        completion(null, DemoNSError(ex.Message));
                    }
                });
            },
            entryPoint: Secrets.EntryPoint,
            environment: PayabliEnvironment.Sandbox,
            telemetryEnabled: true,
            completionHandler: sessionError =>
            {
                MainThread.BeginInvokeOnMainThread(() =>
                {
                    if (sessionError is not null)
                    {
                        ResultLabel.Text = $"✗ Configure failed: {sessionError.LocalizedDescription}";
                        return;
                    }
                    BuildFacades();
                });
            }
        );
    }

    /// <summary>
    /// Runs only once the session is installed, because both facades run on it.
    /// </summary>
    private void BuildFacades()
    {
        PayabliTTP.Create((ttp, ttpError) =>
        {
            MainThread.BeginInvokeOnMainThread(() =>
            {
                if (ttp is null)
                {
                    ResultLabel.Text = $"✗ Configure failed: {ttpError?.LocalizedDescription}";
                    return;
                }
                BuildFacades(ttp);
            });
        });
    }

    private void BuildFacades(PayabliTTP ttp)
    {
        try
        {
            _ttp = ttp;
            _payIn = PayabliPayInObjC.Create(out var payInError);
            if (payInError is not null)
            {
                throw new System.Exception(payInError.LocalizedDescription);
            }

            _eventToken = _ttp.AddEventListener((code, payload) =>
            {
                MainThread.BeginInvokeOnMainThread(() =>
                {
                    var summary = payload.Count > 0 ? $" {payload}" : "";
                    EventLog.Text = $"{code}{summary}\n{EventLog.Text}";
                });
            });

            UpdateSessionBadge();
        }
        catch (System.Exception ex)
        {
            ResultLabel.Text = $"✗ Configure failed: {ex.Message}";
        }
    }

    private async Task<string> FetchAccessTokenFromPartnerBackend()
    {
        // Replace with a real call to your backend that exchanges your
        // server-side clientId + clientSecret for an access_token.
        return await Task.FromResult(Secrets.PlaceholderAccessToken);
    }

    // MARK: - Lifecycle handlers

    private void OnInitializeClicked(object? sender, EventArgs e)
    {
        if (_ttp is null || _isWorking) return;
        SetWorking(true);
        _ttp.Initialize(error =>
        {
            SetWorking(false);
            ResultLabel.Text = error is null
                ? "✓ Initialized"
                : $"✗ {error.Domain}#{error.Code}: {error.LocalizedDescription}";
            UpdateSessionBadge();
        });
    }

    private void OnChargeClicked(object? sender, EventArgs e)
    {
        if (_ttp is null || _isWorking) return;
        if (!decimal.TryParse(AmountEntry.Text, out var amount))
        {
            ResultLabel.Text = "✗ Invalid amount";
            return;
        }

        SetWorking(true);
        var paymentDetails = new PayabliTTPPaymentDetailsObjC(
            new NSDecimalNumber(amount.ToString(System.Globalization.CultureInfo.InvariantCulture)),
            NSDecimalNumber.Zero,
            "USD",
            "MAUI demo sale"
        );
        _ttp.Charge(
            // PayabliTTPPaymentType is `enum : long`, and the binding signature
            // expects `nint`. C# disallows enum -> nint without going through
            // the underlying integral type first, so cast through `long`.
            type: (nint)(long)PayabliTTPPaymentType.Sale,
            paymentDetails: paymentDetails,
            customer: null,
            invoice: null,
            orderDescription: null,
            completion: (result, error) =>
            {
                SetWorking(false);
                ResultLabel.Text = result is not null
                    ? $"✓ Charged · txn {result.PaymentTransId}"
                    : $"✗ {error?.LocalizedDescription ?? "unknown error"}";
                UpdateSessionBadge();
            }
        );
    }

    private async void OnActivateClicked(object? sender, EventArgs e)
    {
        if (_ttp is null || _isWorking) return;
        var code = await DisplayPromptAsync("Activate device", "Enter the activation code");
        if (string.IsNullOrWhiteSpace(code)) return;

        SetWorking(true);
        _ttp.ActivateDevice(code, error =>
        {
            SetWorking(false);
            ResultLabel.Text = error is null
                ? "✓ Device activated"
                : $"✗ {error.LocalizedDescription}";
            UpdateSessionBadge();
        });
    }

    private void OnAddCardClicked(object? sender, EventArgs e)
    {
        if (_payIn is null || _isSubmittingPayIn) return;
        SetSubmittingPayIn(true);
        _payIn.AddCard(
            cardNumber: CardNumberEntry.Text ?? "",
            expiration: CardExpirationEntry.Text ?? "",
            cardholderName: CardHolderEntry.Text ?? "",
            cvv: CardCvvEntry.Text ?? "",
            billingZip: CardZipEntry.Text ?? "",
            createAnonymous: false,
            forceCustomerCreation: true,
            temporary: false,
            source: "maui-demo",
            completion: (method, error) =>
            {
                SetSubmittingPayIn(false);
                ResultLabel.Text = method is not null
                    ? $"✓ Added · stored method {method.StoredMethodId ?? "—"} · {method.ResponseText}"
                    : $"✗ {error?.LocalizedDescription ?? "unknown payment flow error"}";
            }
        );
    }

    private void OnAddAchClicked(object? sender, EventArgs e)
    {
        if (_payIn is null || _isSubmittingPayIn) return;
        SetSubmittingPayIn(true);
        _payIn.AddBankAccount(
            accountNumber: AchAccountEntry.Text ?? "",
            accountType: "Checking",
            holderName: AchHolderEntry.Text ?? "",
            routingNumber: AchRoutingEntry.Text ?? "",
            secCode: "WEB",
            holderType: "personal",
            achValidation: true,
            createAnonymous: false,
            forceCustomerCreation: true,
            temporary: false,
            source: "maui-demo",
            completion: (method, error) =>
            {
                SetSubmittingPayIn(false);
                ResultLabel.Text = method is not null
                    ? $"✓ Added · stored method {method.StoredMethodId ?? "—"} · {method.ResponseText}"
                    : $"✗ {error?.LocalizedDescription ?? "unknown payment flow error"}";
            }
        );
    }

    // MARK: - UI helpers

    private void UpdateSessionBadge()
    {
        if (_ttp is null) { StateBadge.Text = "—"; return; }
        StateBadge.Text = _ttp.SessionState switch
        {
            PayabliTTPSessionState.Idle => "idle",
            PayabliTTPSessionState.AttestingDevice => "attesting",
            PayabliTTPSessionState.FetchingConfig => "config",
            PayabliTTPSessionState.InitializingReader => "reader",
            PayabliTTPSessionState.Ready => "ready",
            PayabliTTPSessionState.SessionExpired => "expired",
            PayabliTTPSessionState.Reinitializing => "reinit",
            PayabliTTPSessionState.PendingActivation => "pending",
            PayabliTTPSessionState.Failed => "failed",
            _ => "?",
        };
    }

    private void SetWorking(bool working)
    {
        _isWorking = working;
        InitializeButton.IsEnabled = !working;
        ChargeButton.IsEnabled = !working;
        ActivateButton.IsEnabled = !working;
    }

    private void SetSubmittingPayIn(bool isSubmitting)
    {
        _isSubmittingPayIn = isSubmitting;
        AddCardButton.IsEnabled = !isSubmitting;
        AddAchButton.IsEnabled = !isSubmitting;
    }

    private static NSError DemoNSError(string message)
    {
        return new NSError(
            new NSString("com.payabli.demo"),
            -1,
            NSDictionary.FromObjectsAndKeys(
                new object[] { new NSString(message) },
                new object[] { NSError.LocalizedDescriptionKey }
            )
        );
    }

    protected override void OnDisappearing()
    {
        _eventToken?.Cancel();
        base.OnDisappearing();
    }
}

/// <summary>
/// Demo-only secrets container. In production fetch the access token from
/// your backend — never embed clientSecret in the app binary.
/// </summary>
internal static class Secrets
{
    public const string EntryPoint = "<YOUR_ENTRY_POINT>";
    public const string PlaceholderAccessToken = "placeholder-token";
}
