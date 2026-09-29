# Card-not-present payments on iOS

Take a card or bank account payment that the payer enters, in the SDK's SwiftUI form or in your own UI.
This guide is part of the [Payabli iOS SDK](../../README.md); set up the SDK there first.

> [!WARNING]
> **This SDK is in beta.** Its public interface can change in ways that aren't backward compatible. See
> [Versioning and support](../../README.md#versioning-and-support).

## Requirements

### Your app

- iOS 16.7 or later as the deployment target. The form runs in the simulator.

### Your account

- OAuth2 credentials with `inboundpayments_create` to charge, authorize and capture,
  `inboundpayments_void` to void, and `tokens_create` to store a payment method.

## Before you start

### Choose the form or your own UI

- **The SDK's form** keeps the card number inside SDK-owned state. It isn't written into a text field's
  `text`, an accessibility value, diagnostics or a callback, so your code never handles a card number.
- **Your own UI** passes `PayabliPayInCardData` you collected to the direct API. Your app then handles card
  numbers and security codes, which brings it into scope for PCI DSS.

## Set up

`PayabliPayIn` runs on a `PayabliSession` built from your configuration. It is `@MainActor`.

```swift
import PayabliSDKCore
import PayabliSDKPayIn

let payIn = PayabliPayIn(
    session: PayabliSession(config: config),
    operation: .capture,
    requestConfiguration: PayabliPayInRequestConfiguration(
        paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34)
    )
)
```

Capture and authorize need a `PayabliPayInRequestConfiguration`, here or on the direct call.

## Take a payment

### Use the SDK's form

`PayabliPayInView` renders a card and bank account form and submits it with the operation you chose:

```swift
import SwiftUI
import PayabliSDKPayIn

struct CheckoutView: View {
    let payIn: PayabliPayIn

    var body: some View {
        PayabliPayInView(
            component: payIn,
            onCompleted: { result in
                // Store the identifiers; don't log them.
                if let stored = result.storedPaymentMethod {
                    order.storedMethodId = stored.storedMethodId
                } else {
                    order.paymentTransId = result.transaction?.paymentTransId
                }
            },
            onError: { error in /* see Outcomes and errors */ }
        )
    }
}
```

To show the form in a sheet, use `.payabliPayInSheet(isPresented:component:configuration:sheetConfiguration:style:onCompleted:onError:)`.
It renders the same form and takes the same configuration and style.

### Call the API from your own UI

```swift
let result = try await payIn.capture(
    PayabliPayInRequest(
        paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34),
        paymentMethod: .card(.init(data: PayabliPayInCardData(
            cardNumber: "4012000098765439",
            expiration: "12/30",
            cardholderName: "Jane Doe",
            cvv: "999",
            billingZip: "12345"
        )))
    )
)
order.paymentTransId = result.transaction?.paymentTransId // store it; don't log it
```

In sandbox, use Payabli's [test cards](https://docs.payabli.com/guides/test-accounts-reference).

### Store a payment method and charge it later

`addCard(_:options:)`, `addBankAccount(_:options:)` and `addPaymentMethod(_:options:)` save a method and
return its stored ID. The form does the same with `.storePaymentMethod`. To charge a saved method, pass
`.stored(.init(method: .card, storedMethodId: id))` as the payment method.

### Authorize, then capture

`authorize(_:)` holds an amount on a card, a stored card or a cloud device without charging it. The form
authorizes a card only. `captureAuthorizedTransaction(_:)` captures that authorization later, and `voidTransaction(_:)`
releases it or voids a transaction that hasn't settled.

### Retry safely

A charge always sends an idempotency key. The SDK mints one per call when you don't set
`PayabliPayInRequest.idempotencyKey`, so calling again without your own key is a second payment, not a
retry. Don't resend a charge whose outcome is unknown. Find the transaction first.

## Outcomes and errors

A returned result means what the call did, which depends on the call:

| Call | A result means | `transactionFailed` means |
|---|---|---|
| `capture(_:)` | The payment was charged | Not charged |
| `authorize(_:)` | An amount is held. Nothing is charged until you capture it | No hold was placed |
| `captureAuthorizedTransaction(_:)` | The held amount was charged | The hold wasn't captured |
| `voidTransaction(_:)` | The transaction was voided | The void was refused. It doesn't mean the original payment wasn't charged |

For a charge, the outcomes are the ones in the root README's
[Handle the outcome](../../README.md#handle-the-outcome):

| Result | Outcome | What to do |
|---|---|---|
| The call returns a `PayabliPayInResult` | Charged, or saved | Store the transaction ID or the stored method ID |
| `PayabliPayInError.transactionFailed`, for example a decline | Not charged | You can retry |
| `PayabliPayInError.invalidInput`, `.submissionInProgress` | Not charged; refused before anything was sent | Fix the input, or wait for the running submission |
| A core `PayabliError` whose `code` is `.tokenProviderFailed` | Not charged; your token provider failed | Fix the token provider |
| `PayabliPayInError.submissionInterrupted` | Unknown | Find the transaction by `orderId` in the Payabli portal before charging again |
| A core `PayabliError`, such as a validation failure, a refused credential or a rate limit | Not charged; the service's answer | Branch on its `code` |
| `PayabliPayInTokenStorageError` | The method wasn't saved | `invalidInput` was refused before sending; `saveFailed` is the service's answer |

Show `error.localizedDescription` to the payer, since it names what the service rejected. Don't log it: it
can quote what was submitted. Log `(error as? any PayabliError)?.code` instead.

## Reference

### Operations

| Operation | What a form submission does |
|---|---|
| `.storePaymentMethod` | Saves the card or bank account as a stored payment method. This is the default |
| `.capture` | Charges the payment method |
| `.authorize` | Authorizes a card without capturing it |

### Methods

| Method | What it does |
|---|---|
| `capture(_:)` | Charges a card, bank account or stored payment method |
| `authorize(_:)` | Authorizes a card, a stored card or a cloud device |
| `captureAuthorizedTransaction(_:)` | Captures an earlier authorization |
| `voidTransaction(_:)` | Voids a transaction that hasn't settled |
| `addCard(_:options:)`, `addBankAccount(_:options:)`, `addPaymentMethod(_:options:)` | Saves a payment method and returns its stored ID |

### Form configuration

`PayabliPayInFormConfiguration` chooses what the form shows:

| Parameter | Sets |
|---|---|
| `allowedMethods`, `defaultMethod` | Card, bank account, or both, and which opens first |
| `cardFieldOrder`, `bankFieldOrder`, `cardSections`, `bankSections` | The fields, their order, and their sections |
| `requiredFields`, `hiddenValues`, `options` | Fields the payer must fill, values sent without a field, and form options |
| `labels`, `labelLayout`, `showsFieldLabels`, `hiddenFieldLabels` | Wording, and where labels sit or whether they show |
| `formatting`, `inputSizing`, `cardBrandIconPlacement` | Formatting, field sizes, and the card brand icon |
| `paymentSummary` | The amount and fee rows |

`PayabliPayInLabels(fieldPlaceholders:)` sets placeholders per field. `labelLayout: .placeholder` or
`showsFieldLabels: false` hides the visible labels and keeps the accessible ones.

Group fields with `PayabliPayInFieldSection`:

```swift
PayabliPayInFieldSection(
    title: "Card Information",
    fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip],
    inputVerticalSpacing: 4,
    inputHorizontalSpacing: 8,
    fieldVerticalSpacings: [.cardNumber: 2, .cardCvv: 2]
)
```

Capture and authorize forms add a **Payment Information** section with the amount and fee. A form storing
a payment method leaves it out.

### Styling

`PayabliPayInStyle`, applied with `.payabliPayInStyle(_:)`, sets:

- the title, subtitle, label, section title, error and submit button text styles;
- the input font, with `input.uiFont` for the UIKit-backed text fields;
- the input text, placeholder, background, focus, border and picker icon colors;
- the layout spacing.

A custom font must be registered by your app: add the files to the app target, list them under
`UIAppFonts` in `Info.plist`, and use `Font.custom(_:size:)` for SwiftUI text and `UIFont(name:size:)`
for the text fields.

### Accessibility

- Touch targets of at least 44 points.
- Accessible labels, including when the visible labels are hidden.
- Secure accessibility values for the card number and CVV, and for the account number while
  `formatting.masksAccountNumber` is on, which is the default. The routing number isn't masked.
- Announcements when card number validation changes.
- Dynamic Type, with paired fields stacked at accessibility sizes.

## Go live

- `.production` and a production entry point, with credentials carrying the permissions in
  [Requirements](#requirements).
- Production card details only. The sandbox test cards don't work in production.
- The transaction ID stored with every order, so any outcome can be reconciled.

## Related docs

- [Payabli iOS SDK](../../README.md): setup, the token endpoint, outcomes and go-live
- [Tap to Pay on iPhone](../PayabliSDKTapToPay/README.md)
- [`Documentation/PayInIntegrationGuide.md`](../../Documentation/PayInIntegrationGuide.md): every
  configuration and styling option, with examples
- [Sample app](../../Example/PayabliDemo/)
- [Pay In API reference](https://docs.payabli.com/developers/api-reference/moneyin/get-details-for-a-processed-transaction)
