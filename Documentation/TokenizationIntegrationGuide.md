# Payabli Tokenization Integration Guide

This guide is the shortest path from "I linked the SDK" to "my app can save a
card or ACH account as a Payabli stored payment method."

For the full feature reference, supported fields, and style samples, see
[`TokenizationOverview.md`](TokenizationOverview.md).

## Integration Checklist

1. Add the `PayabliSDKTokenization` product to the host app target.
2. Build a backend endpoint that returns a Payabli access token for
   tokenization.
3. Create a `PayabliTokenization` component in the app.
4. Choose one UI path:
   - Use `PayabliTokenizationView` for an inline SwiftUI component.
   - Use `.payabliTokenizationSheet(...)` for the SDK-provided bottom sheet.
   - Use the Flutter or MAUI bridge when integrating from those frameworks.
5. Configure visible optional fields, hidden values, labels, formatting,
   ordering, input sizing, and style.
6. Store only `storedMethodId` and safe metadata after success.
7. Handle `PayabliError` failures and show an app-specific retry path.

## Backend Requirement

The mobile app must not contain a private Payabli API key. Instead, expose a
backend endpoint such as:

```http
POST /payabli/token-storage/access-token
Authorization: Bearer <your-app-session>
```

That backend endpoint should authenticate the app user, use server-side Payabli
credentials or server-side token policy, and return only the access token that
the mobile app needs for `POST /api/TokenStorage/add`.

For sandbox, the backend exchange can call Payabli's server-side token endpoint
with your sandbox `clientId` and `clientSecret`:

```bash
curl --location 'https://api-sandbox.payabli.com/api/v2/token/serverside' \
  --header 'Content-Type: application/json' \
  --data '{
    "clientId": "{clientId}",
    "clientSecret": "{clientSecret}"
  }'
```

QA uses the same path with the QA host:

```text
https://api-qa.payabli.com/api/v2/token/serverside
```

Payabli returns:

```json
{
  "token_type": "Bearer",
  "access_token": "{access_token}",
  "expires_in": 3600
}
```

The mobile-facing backend endpoint can translate that to either
`{ "accessToken": "..." }` or pass through `access_token`; the sample accepts
both response fields.

The iOS side then wires that endpoint into the component:

```swift
let tokenization = PayabliTokenization(
    entryPoint: "<PAYABLI_ENTRY_POINT>",
    environment: .sandbox,
    accessTokenProvider: {
        try await backend.fetchTokenStorageAccessToken()
    }
)
```

Use `.production` only after the backend is returning production-scoped access
tokens.

## Key Decisions

Before implementation, decide:

- Presentation: embed `PayabliTokenizationView` inline or present the same form
  through `.payabliTokenizationSheet(...)`.
- Method coverage: card-only, ACH-only, or a segmented card/ACH form.
- Customer behavior: for customer-owned reusable methods, pass
  `createAnonymous: false`, `forceCustomerCreation: true`, and
  `temporary: false`.
- Error placement: render API failures at the top of the component or above
  the submit button with `errorMessagePlacement`.
- Diagnostics: enable redacted request/response logs only for local and QA
  builds.

## Native SwiftUI Turnkey Component

Use this path when you want Payabli to own the secure input form and validation
inside SwiftUI.

```swift
import SwiftUI
import PayabliSDKCore
import PayabliSDKTokenization

struct SavePaymentMethodScreen: View {
    @StateObject private var tokenization = PayabliTokenization(
        entryPoint: "<PAYABLI_ENTRY_POINT>",
        environment: .sandbox,
        accessTokenProvider: {
            try await Backend.shared.fetchTokenStorageAccessToken()
        }
    )

    var body: some View {
        PayabliTokenizationView(
            component: tokenization,
            configuration: configuration,
            onTokenized: { method in
                guard let storedMethodId = method.storedMethodId else {
                    return
                }
                saveStoredMethodId(storedMethodId)
                inspectFullResponse(method.apiResponse)
            },
            onError: { error in
                present(error)
            }
        )
        .payabliTokenizationStyle(style)
        .padding()
    }

    private var configuration: PayabliTokenizationFormConfiguration {
        PayabliTokenizationFormConfiguration(
            allowedMethods: [.card, .ach],
            defaultMethod: .card,
            cardFieldOrder: [
                .cardholderName,
                .cardNumber,
                .cardExpiration,
                .cardCvv,
                .cardZip
            ],
            achFieldOrder: [
                .achHolder,
                .achRouting,
                .achAccount,
                .achAccountType
            ],
            hiddenValues: PayabliTokenizationHiddenValues(
                achHolderType: .personal,
                achSecCode: .web,
                methodDescription: "Primary payment method",
                customerData: PayabliTokenizationCustomerData(
                    customerNumber: "customer-123"
                )
            ),
            options: PayabliTokenizationOptions(
                achValidation: true,
                createAnonymous: false,
                forceCustomerCreation: true,
                temporary: false,
                source: "ios-app"
            ),
            labelLayout: .external,
            formatting: PayabliTokenizationFormatting(
                insertsCardNumberSpaces: true,
                expirationSeparator: "/",
                masksACHAccountEntry: true
            ),
            inputSizing: PayabliTokenizationInputSizing(
                defaultSize: PayabliTokenizationInputSize(height: 52),
                fieldSizes: [
                    .cardExpiration: PayabliTokenizationInputSize(width: 132, height: 48),
                    .cardCvv: PayabliTokenizationInputSize(width: 104, height: 48)
                ]
            ),
            cardBrandIconPlacement: .trailing,
            errorMessagePlacement: .aboveSubmitButton
        )
    }

    private var style: PayabliTokenizationStyle {
        PayabliTokenizationStyle(
            accentColor: .blue,
            input: PayabliTokenizationInputStyle(cornerRadius: 8),
            submitButton: PayabliTokenizationSubmitButtonStyle(cornerRadius: 8)
        )
    }
}
```

### Common Form Recipes

Card only:

```swift
PayabliTokenizationFormConfiguration(
    allowedMethods: [.card],
    cardFieldOrder: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip]
)
```

ACH only:

```swift
PayabliTokenizationFormConfiguration(
    allowedMethods: [.ach],
    defaultMethod: .ach,
    achFieldOrder: [.achHolder, .achRouting, .achAccount, .achAccountType],
    hiddenValues: PayabliTokenizationHiddenValues(
        achSecCode: .web,
        achHolderType: .personal
    ),
    options: PayabliTokenizationOptions(achValidation: true)
)
```

Placeholder labels:

```swift
PayabliTokenizationFormConfiguration(
    labelLayout: .placeholder,
    labels: PayabliTokenizationLabels(
        title: "Add Payment Method",
        submitButton: "Save"
    )
)
```

Submit button text:

```swift
PayabliTokenizationFormConfiguration(
    labels: PayabliTokenizationLabels(submitButton: "Save Payment Method")
)
```

Card brand icon on the left:

```swift
PayabliTokenizationFormConfiguration(
    cardBrandIconPlacement: .leading
)
```

Use `.trailing` for the right side, or `.hidden` to suppress the icon.

Card ZIP is always required by the component. If `.cardZip` is omitted from
`cardFieldOrder`, the SDK appends it to the rendered card fields.

## Native SwiftUI Sheet

Use this path when the host app wants a bottom-sheet "add payment method"
experience while still letting Payabli own the form UI, validation, submission,
and error rendering.

```swift
struct CheckoutScreen: View {
    @State private var isTokenizationPresented = false
    @StateObject private var tokenization = PayabliTokenization(
        entryPoint: "<PAYABLI_ENTRY_POINT>",
        environment: .sandbox,
        accessTokenProvider: {
            try await Backend.shared.fetchTokenStorageAccessToken()
        }
    )

    var body: some View {
        Button("Add payment method") {
            isTokenizationPresented = true
        }
        .payabliTokenizationSheet(
            isPresented: $isTokenizationPresented,
            component: tokenization,
            configuration: PayabliTokenizationFormConfiguration(
                allowedMethods: [.card],
                labels: PayabliTokenizationLabels(
                    title: "Add Card",
                    submitButton: "Save Card"
                ),
                cardBrandIconPlacement: .trailing
            ),
            sheetConfiguration: PayabliTokenizationSheetConfiguration(
                dismissButton: .back,
                dismissesOnTokenized: true,
                detents: [.medium, .large],
                sizesToContentWhenPossible: true,
                expandsToLargeWhenContentDoesNotFit: true
            ),
            style: PayabliTokenizationStyle(
                accentColor: .blue,
                input: PayabliTokenizationInputStyle(cornerRadius: 8),
                submitButton: PayabliTokenizationSubmitButtonStyle(cornerRadius: 8)
            ),
            onTokenized: { method in
                saveStoredMethodId(method.storedMethodId)
            },
            onError: { error in
                present(error)
            }
        )
    }
}
```

The sheet modifier reuses `PayabliTokenizationView` internally. By default it
moves `PayabliTokenizationLabels.title` and `subtitle` into the sheet header so
the form does not render a duplicate title. Set
`movesFormHeaderToSheetHeader: false` when the host app wants the form header
inside the scrollable content. By default, the sheet sizes itself to the
rendered form height when it fits on screen so the inputs and submit button stay
grouped together. When the form is taller than the available sheet height and
`.large` is included in the detents, the sheet opens to `.large`.

## Response Handling

Always treat the returned `PayabliTokenizedMethod` as the source of truth.

```swift
func handleTokenized(_ method: PayabliTokenizedMethod) {
    guard let storedMethodId = method.storedMethodId else {
        return
    }

    // Save this in your app/backend for future transactions.
    save(storedMethodId)

    // Available for support workflows, analytics, and custom handling.
    let responseText = method.apiResponse.responseText
    let resultText = method.apiResponse.responseData?.resultText
    let customerId = method.apiResponse.responseData?.customerId
}
```

Do not store card numbers, CVVs, ACH account numbers, routing numbers, or
access tokens.

## Development Diagnostics

For local or QA validation, enable redacted diagnostics on the tokenization
component:

```swift
let tokenization = PayabliTokenization(
    entryPoint: Secrets.entryPoint,
    environment: .sandbox,
    accessTokenProvider: {
        try await Backend.shared.fetchTokenStorageAccessToken()
    },
    diagnostics: .enabled { entry in
        print("[\(entry.phase.rawValue)] \(entry.method) \(entry.url)")
        print(entry.headers)
        print(entry.body ?? "")
    }
)
```

Developers access logs through that handler. Each
`PayabliTokenizationDiagnosticEntry` contains the request/response phase, full
URL with query parameters, redacted headers, redacted JSON body, HTTP status,
elapsed duration, and any transport failure text. Sensitive values are replaced
before the handler is called.

## Error Handling

```swift
do {
    let method = try await tokenization.tokenize(paymentMethod: paymentMethod)
    handleTokenized(method)
} catch let error as PayabliTokenizationError {
    show(error.reason)
} catch let error as any PayabliError {
    show(error.reason)
} catch {
    show("Unable to save payment method.")
}
```

Expected integration errors include:

- Invalid card, expiration, CVV, ACH account, routing number, or ACH holder
- Empty or missing access token
- Payabli decline or failed tokenization response
- HTTP authentication/authorization/server errors from the shared Core error
  mapping

## Flutter Integration

The Flutter bridge exposes tokenization over the existing
`com.payabli.sdk/taptopay` method channel.

Example app:

- `Example/PayabliFlutterDemo`
- Bridge package wrapper: `Bridges/Flutter`

Configure:

```dart
await PayabliTokenization.configure(
  accessTokenProvider: Secrets.fetchTokenizationAccessToken,
  entryPoint: Secrets.entryPoint,
  environment: PayabliEnvironment.sandbox,
);
```

Tokenize card:

```dart
final method = await PayabliTokenization.tokenizeCard(
  cardNumber: cardNumber,
  expiration: expiration,
  cardholderName: cardholderName,
  cvv: cvv,
  billingZip: billingZip,
  createAnonymous: false,
  forceCustomerCreation: true,
  temporary: false,
);
```

Tokenize ACH:

```dart
final method = await PayabliTokenization.tokenizeACH(
  accountNumber: accountNumber,
  accountType: 'Checking',
  holderName: holderName,
  routingNumber: routingNumber,
  secCode: 'WEB',
  holderType: 'personal',
  createAnonymous: false,
  forceCustomerCreation: true,
  temporary: false,
);
```

The Dart result exposes `storedMethodId`, `methodReferenceId`, `resultCode`,
`resultText`, `customerId`, `responseText`, and `apiResponse`.

## .NET MAUI Integration

The MAUI binding exposes the Objective-C-compatible tokenization wrapper.

Example app:

- `Example/PayabliMAUIDemo`
- Binding project: `Bridges/MAUI`

Build and copy the release frameworks before building the MAUI host:

```bash
./Scripts/build_release_frameworks.sh
mkdir -p Bridges/MAUI/Frameworks
cp -R build/release/PayabliSDKCore.xcframework Bridges/MAUI/Frameworks/
cp -R build/release/PayabliSDKTapToPay.xcframework Bridges/MAUI/Frameworks/
cp -R build/release/PayabliSDKTokenization.xcframework Bridges/MAUI/Frameworks/
cp -R build/release/PayabliCardReaderCore.xcframework Bridges/MAUI/Frameworks/
```

The sample targets .NET 10 iOS:

```bash
cd Example/PayabliMAUIDemo
dotnet workload restore
dotnet build -f net10.0-ios
```

If the SDK was installed system-wide, workload restore may require elevated
privileges. If restore cannot infer workloads from the project graph, install
the workloads directly:

```bash
sudo dotnet workload install maui-ios mobile-librarybuilder
```

Configure:

```csharp
_tokenization = new PayabliTokenizationObjC(
    accessTokenHandler: completion =>
    {
        Task.Run(async () =>
        {
            try
            {
                var token = await FetchAccessTokenFromPartnerBackend();
                completion(token, null);
            }
            catch (Exception ex)
            {
                completion(null, DemoNSError(ex.Message));
            }
        });
    },
    entryPoint: Secrets.EntryPoint,
    environment: PayabliEnvironment.Sandbox
);
```

Tokenize card:

```csharp
_tokenization.TokenizeCard(
    cardNumber: cardNumber,
    expiration: expiration,
    cardholderName: cardholderName,
    cvv: cvv,
    billingZip: billingZip,
    createAnonymous: false,
    forceCustomerCreation: true,
    temporary: false,
    source: "maui-app",
    completion: (method, error) =>
    {
        if (method is not null)
        {
            Save(method.StoredMethodId);
        }
    }
);
```

Tokenize ACH:

```csharp
_tokenization.TokenizeACH(
    accountNumber: accountNumber,
    accountType: "Checking",
    holderName: holderName,
    routingNumber: routingNumber,
    secCode: "WEB",
    holderType: "personal",
    achValidation: true,
    createAnonymous: false,
    forceCustomerCreation: true,
    temporary: false,
    source: "maui-app",
    completion: (method, error) =>
    {
        if (method is not null)
        {
            Save(method.StoredMethodId);
        }
    }
);
```

The MAUI result exposes `StoredMethodId`, `MethodReferenceId`, `ResultCode`,
`ResultText`, `CustomerId`, `ResponseText`, and `ApiResponse`.

## Visual QA

Use the native SwiftUI sample in `Example/PayabliDemo` for component styling QA
on Simulator. Tap to Pay still requires a physical iPhone, but tokenization can
be visually checked in Simulator.

```bash
xcodebuild build -scheme PayabliSDK-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

The Flutter and MAUI demos include their own tokenization screens for bridge
visual QA.
