# Payabli Payment Method Integration Guide

This guide is the shortest path from "I linked the SDK" to "my app can save a
card or ACH account as a Payabli stored payment method."

For the full feature reference, supported fields, and style samples, see
[`PaymentMethodOverview.md`](PaymentMethodOverview.md).

## Integration Checklist

1. Add the `PayabliSDKPaymentMethod` product to the host app target.
2. Build a backend endpoint that returns a Payabli access token for
   payment method.
3. Create a `PayabliPaymentMethod` component in the app.
4. Choose one UI path:
   - Use `PayabliPaymentMethodView` for an inline SwiftUI component.
   - Use `.payabliPaymentMethodSheet(...)` for the SDK-provided bottom sheet.
   - Use the Flutter or MAUI bridge when integrating from those frameworks.
5. Configure visible optional fields, additional required fields, hidden
   values, labels, formatting, ordering, input sizing, and style.
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
let paymentMethod = PayabliPaymentMethod(
    entryPoint: "<PAYABLI_ENTRY_POINT>",
    environment: .sandbox,
    accessTokenProvider: {
        try await backend.fetchPaymentMethodAccessToken()
    }
)
```

Use `.production` only after the backend is returning production-scoped access
tokens.

## Key Decisions

Before implementation, decide:

- Presentation: embed `PayabliPaymentMethodView` inline or present the same form
  through `.payabliPaymentMethodSheet(...)`.
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
import PayabliSDKPaymentMethod

struct SavePaymentMethodScreen: View {
    @StateObject private var paymentMethod = PayabliPaymentMethod(
        entryPoint: "<PAYABLI_ENTRY_POINT>",
        environment: .sandbox,
        accessTokenProvider: {
            try await Backend.shared.fetchPaymentMethodAccessToken()
        }
    )

    var body: some View {
        PayabliPaymentMethodView(
            component: paymentMethod,
            configuration: configuration,
            onPaymentMethodAdded: { method in
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
        .payabliPaymentMethodStyle(style)
        .padding()
    }

    private var configuration: PayabliPaymentMethodFormConfiguration {
        PayabliPaymentMethodFormConfiguration(
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
            hiddenValues: PayabliPaymentMethodHiddenValues(
                achHolderType: .personal,
                achSecCode: .web,
                methodDescription: "Primary payment method",
                customerData: PayabliPaymentMethodCustomerData(
                    customerNumber: "customer-123"
                )
            ),
            options: PayabliPaymentMethodOptions(
                achValidation: true,
                createAnonymous: false,
                forceCustomerCreation: true,
                temporary: false,
                source: "ios-app"
            ),
            labelLayout: .external,
            formatting: PayabliPaymentMethodFormatting(
                insertsCardNumberSpaces: true,
                expirationSeparator: "/",
                masksACHAccountEntry: true
            ),
            inputSizing: PayabliPaymentMethodInputSizing(
                defaultSize: PayabliPaymentMethodInputSize(height: 52),
                fieldSizes: [
                    .cardExpiration: PayabliPaymentMethodInputSize(width: 132, height: 48),
                    .cardCvv: PayabliPaymentMethodInputSize(width: 104, height: 48)
                ]
            ),
            cardBrandIconPlacement: .trailing,
            errorMessagePlacement: .aboveSubmitButton
        )
    }

    private var style: PayabliPaymentMethodStyle {
        PayabliPaymentMethodStyle(
            accentColor: .blue,
            input: PayabliPaymentMethodInputStyle(cornerRadius: 8),
            submitButton: PayabliPaymentMethodSubmitButtonStyle(cornerRadius: 8)
        )
    }
}
```

### Common Form Recipes

Card only:

```swift
PayabliPaymentMethodFormConfiguration(
    allowedMethods: [.card],
    cardFieldOrder: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip]
)
```

ACH only:

```swift
PayabliPaymentMethodFormConfiguration(
    allowedMethods: [.ach],
    defaultMethod: .ach,
    achFieldOrder: [.achHolder, .achRouting, .achAccount, .achAccountType],
    hiddenValues: PayabliPaymentMethodHiddenValues(
        achSecCode: .web,
        achHolderType: .personal
    ),
    options: PayabliPaymentMethodOptions(achValidation: true)
)
```

Require optional fields:

```swift
PayabliPaymentMethodFormConfiguration(
    requiredFields: [.billingEmail, .methodDescription]
)
```

Placeholder labels:

```swift
PayabliPaymentMethodFormConfiguration(
    labelLayout: .placeholder,
    labels: PayabliPaymentMethodLabels(
        title: "Add Payment Method",
        submitButton: "Save"
    )
)
```

Submit button text:

```swift
PayabliPaymentMethodFormConfiguration(
    labels: PayabliPaymentMethodLabels(submitButton: "Save Payment Method")
)
```

Card brand icon on the left:

```swift
PayabliPaymentMethodFormConfiguration(
    cardBrandIconPlacement: .leading
)
```

Use `.trailing` for the right side, or `.hidden` to suppress the icon.

Card CVV and ZIP are always required by the component. If either field is
omitted from `cardFieldOrder`, the SDK appends it to the rendered card fields.

Input length limits are enforced in the UI and again before a request is sent:

| Field | Limit |
|---|---|
| Name on card | 60 characters |
| Card number | 12 to 19 digits; entry is capped at 19 digits |
| CVV | 3 to 4 digits; entry is capped at 4 digits |
| ZIP/postal code | 12 characters, covering US ZIP+4, Canada, and common international postal formats |
| ACH routing number | Exactly 9 digits for US banks |
| ACH account number | 4 to 17 digits for US ACH |
| ACH account holder | 60 characters |

## Native SwiftUI Sheet

Use this path when the host app wants a bottom-sheet "add payment method"
experience while still letting Payabli own the form UI, validation, submission,
and error rendering.

```swift
struct CheckoutScreen: View {
    @State private var isPaymentMethodPresented = false
    @StateObject private var paymentMethod = PayabliPaymentMethod(
        entryPoint: "<PAYABLI_ENTRY_POINT>",
        environment: .sandbox,
        accessTokenProvider: {
            try await Backend.shared.fetchPaymentMethodAccessToken()
        }
    )

    var body: some View {
        Button("Add payment method") {
            isPaymentMethodPresented = true
        }
        .payabliPaymentMethodSheet(
            isPresented: $isPaymentMethodPresented,
            component: paymentMethod,
            configuration: PayabliPaymentMethodFormConfiguration(
                allowedMethods: [.card],
                labels: PayabliPaymentMethodLabels(
                    title: "Add Card",
                    submitButton: "Save Card"
                ),
                cardBrandIconPlacement: .trailing
            ),
            sheetConfiguration: PayabliPaymentMethodSheetConfiguration(
                dismissButton: .back,
                dismissesOnSuccess: true,
                detents: [.medium, .large],
                sizesToContentWhenPossible: true,
                expandsToLargeWhenContentDoesNotFit: true
            ),
            style: PayabliPaymentMethodStyle(
                accentColor: .blue,
                input: PayabliPaymentMethodInputStyle(cornerRadius: 8),
                submitButton: PayabliPaymentMethodSubmitButtonStyle(cornerRadius: 8)
            ),
            onPaymentMethodAdded: { method in
                saveStoredMethodId(method.storedMethodId)
            },
            onError: { error in
                present(error)
            }
        )
    }
}
```

The sheet modifier reuses `PayabliPaymentMethodView` internally. By default it
moves `PayabliPaymentMethodLabels.title` and `subtitle` into the sheet header so
the form does not render a duplicate title. Set
`movesFormHeaderToSheetHeader: false` when the host app wants the form header
inside the scrollable content. By default, the sheet sizes itself to the
rendered form height when it fits on screen so the inputs and submit button stay
grouped together. When the form is taller than the available sheet height and
`.large` is included in the detents, the sheet opens to `.large`.

## Response Handling

Always treat the returned `PayabliStoredPaymentMethod` as the source of truth.

```swift
func handlePaymentMethodAdded(_ method: PayabliStoredPaymentMethod) {
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

For local or QA validation, enable redacted diagnostics on the payment method
component:

```swift
let paymentMethod = PayabliPaymentMethod(
    entryPoint: Secrets.entryPoint,
    environment: .sandbox,
    accessTokenProvider: {
        try await Backend.shared.fetchPaymentMethodAccessToken()
    },
    diagnostics: .enabled { entry in
        print("[\(entry.phase.rawValue)] \(entry.method) \(entry.url)")
        print(entry.headers)
        print(entry.body ?? "")
    }
)
```

Developers access logs through that handler. Each
`PayabliPaymentMethodDiagnosticEntry` contains the request/response phase, full
URL with query parameters, redacted headers, redacted JSON body, HTTP status,
elapsed duration, and any transport failure text. Sensitive values are replaced
before the handler is called.

## Local QA Mock Responses

The sample app includes local success and failure mocks for UI/UX validation.
Use these only in local development or QA builds; production apps should let
`PayabliPaymentMethod` create its default network transport.

Enable one mock in `Example/PayabliDemo/Secrets.swift`:

```swift
static let paymentMethodMockSuccessEnabled = true
static let paymentMethodMockFailureEnabled = false
```

or:

```swift
static let paymentMethodMockSuccessEnabled = false
static let paymentMethodMockFailureEnabled = true
```

If both flags are enabled, the failure mock wins. Mock mode returns a placeholder
bearer token from the sample app and does not call
`fetchPaymentMethodAccessToken()`.

The success mock returns:

```json
{
  "isSuccess": true,
  "responseText": "Success",
  "responseData": {
    "referenceId": "qa-mock-stored-method",
    "resultCode": 1,
    "resultText": "Approved",
    "methodReferenceId": "qa-mock-method-reference",
    "customerId": 123456789
  }
}
```

The failure mock returns:

```json
{
  "isSuccess": false,
  "responseText": "Error",
  "responseCode": 6000,
  "responseData": {
    "explanation": "Invalid Card",
    "todoAction": "Please check your card details and try again."
  }
}
```

## Error Handling

```swift
do {
    let input = PayabliPaymentMethodInput.card(cardData)
    let method = try await paymentMethod.addPaymentMethod(input)
    handlePaymentMethodAdded(method)
} catch let error as PayabliPaymentMethodError {
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
- Payabli decline or failed payment method response
- HTTP authentication/authorization/server errors from the shared Core error
  mapping

## Flutter Integration

The Flutter bridge exposes payment method over the existing
`com.payabli.sdk/taptopay` method channel.

Example app:

- `Example/PayabliFlutterDemo`
- Bridge package wrapper: `Bridges/Flutter`

Configure:

```dart
await PayabliPaymentMethod.configure(
  accessTokenProvider: Secrets.fetchPaymentMethodAccessToken,
  entryPoint: Secrets.entryPoint,
  environment: PayabliEnvironment.sandbox,
);
```

Add a card:

```dart
final method = await PayabliPaymentMethod.addCard(
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

Add ACH:

```dart
final method = await PayabliPaymentMethod.addACH(
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

The MAUI binding exposes the Objective-C-compatible payment method wrapper.

Example app:

- `Example/PayabliMAUIDemo`
- Binding project: `Bridges/MAUI`

Build and copy the release frameworks before building the MAUI host:

```bash
./Scripts/build_release_frameworks.sh
mkdir -p Bridges/MAUI/Frameworks
cp -R build/release/PayabliSDKCore.xcframework Bridges/MAUI/Frameworks/
cp -R build/release/PayabliSDKTapToPay.xcframework Bridges/MAUI/Frameworks/
cp -R build/release/PayabliSDKPaymentMethod.xcframework Bridges/MAUI/Frameworks/
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
_paymentMethod = new PayabliPaymentMethodObjC(
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

Add a card:

```csharp
_paymentMethod.AddCard(
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

Add ACH:

```csharp
_paymentMethod.AddACH(
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
on Simulator. Tap to Pay still requires a physical iPhone, but payment method can
be visually checked in Simulator.

```bash
xcodebuild build -scheme PayabliSDK-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

The Flutter and MAUI demos include their own payment method screens for bridge
visual QA.
