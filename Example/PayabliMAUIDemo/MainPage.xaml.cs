using Foundation;
using Payabli;
using UIKit;

namespace PayabliMauiDemo;

public partial class MainPage : ContentPage
{
    public MainPage()
    {
        InitializeComponent();
        ConfigurePayabli();
    }

    /// <summary>
    /// Configure PayabliPayIn with an access token obtained from the partner
    /// backend. Never embed the clientSecret in the mobile binary.
    /// </summary>
    private async void ConfigurePayabli()
    {
        try
        {
            var accessToken = await FetchAccessTokenFromPartnerBackend();
            var config = new PayabliConfig(
                accessToken: accessToken,
                tokenRefresh: (completion) =>
                {
                    // Call partner backend on refresh demand and hand back a fresh token.
                    Task.Run(async () =>
                    {
                        try
                        {
                            var fresh = await FetchAccessTokenFromPartnerBackend();
                            completion(fresh, null);
                        }
                        catch (Exception ex)
                        {
                            completion(null, new NSError(new NSString(ex.Message), 0));
                        }
                    });
                },
                entryPoint: "<YOUR_ENTRY_POINT>",
                environment: PayabliEnvironment.Sandbox,
                telemetryEnabled: true
            );
            PayabliPayIn.Shared.Configure(config, PayabliTheme.Default);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"PayabliSDK configure failed: {ex.Message}");
        }
    }

    private async Task<string> FetchAccessTokenFromPartnerBackend()
    {
        // TODO: call your backend's /payabli/token endpoint.
        await Task.Delay(1);
        throw new NotImplementedException("Wire me to your backend.");
    }

    private void OnTokenizeClicked(object sender, EventArgs e)
    {
        var rootVc = UIApplication.SharedApplication.KeyWindow?.RootViewController;
        if (rootVc == null) return;

        var vc = PayabliPayIn.Shared.CreateTokenizationViewController(
            PayabliPaymentType.Card,
            customerId: 4440,
            (token, error) =>
            {
                ResultLabel.Text = token != null ? $"Token: {token}" : $"Error: {error?.LocalizedDescription}";
            });
        rootVc.PresentViewController(vc, animated: true, completionHandler: null);
    }
}
