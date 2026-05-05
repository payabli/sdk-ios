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
    private PayabliTTPEventToken? _eventToken;
    private bool _isWorking;

    public MainPage()
    {
        InitializeComponent();
        ConfigurePayabli();
    }

    /// <summary>
    /// Bootstraps a single PayabliTTP instance with credentials from the
    /// partner backend. The token-refresh callback fires whenever the SDK
    /// needs a new access token — wire it to your own /payabli/token
    /// endpoint. Never embed the clientSecret in the mobile binary.
    /// </summary>
    private async void ConfigurePayabli()
    {
        try
        {
            var initialToken = await FetchAccessTokenFromPartnerBackend();
            _ttp = new PayabliTTP(
                accessToken: initialToken,
                tokenRefreshHandler: (completion) =>
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
                            var nsError = new NSError(
                                new NSString("com.payabli.demo"),
                                -1,
                                NSDictionary.FromObjectsAndKeys(
                                    new object[] { new NSString(ex.Message) },
                                    new object[] { NSError.LocalizedDescriptionKey }
                                )
                            );
                            completion(null, nsError);
                        }
                    });
                },
                entryPoint: Secrets.EntryPoint,
                appId: Secrets.AppId,
                environment: PayabliEnvironment.Sandbox
            );

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
        _ttp.Charge(
            amount: NSDecimalNumber.FromString(amount.ToString(System.Globalization.CultureInfo.InvariantCulture)),
            // PayabliTTPPaymentType is `enum : long`, and the binding signature
            // expects `nint`. C# disallows enum -> nint without going through
            // the underlying integral type first, so cast through `long`.
            type: (nint)(long)PayabliTTPPaymentType.Sale,
            serviceFee: NSDecimalNumber.Zero,
            customer: null,
            order: null,
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
            PayabliTTPSessionState.Error => "error",
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
    public const string AppId = "<TEAM_ID>.<BUNDLE_ID>";
    public const string PlaceholderAccessToken = "placeholder-token";
}
