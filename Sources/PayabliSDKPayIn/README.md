# Card-not-present payments on iOS

Take a card or bank account payment that the payer enters, in the SDK's SwiftUI form or in your own UI.
This guide is part of the [Payabli iOS SDK](../../README.md); set up the SDK and its session there first.

> [!IMPORTANT]
> **Notice:** This SDK is in beta. Its public interface can change in ways that aren't backward compatible. See
> [Versioning and support](../../README.md#versioning-and-support).

## Requirements

### Your app

- iOS 16.7 or later as the deployment target. The form runs in the simulator.

### Your account

OAuth2 credentials with a permission for each operation you use:

| Operation | Permission |
|---|---|
| `capture(_:)`, `authorize(_:)`, `captureAuthorizedTransaction(_:)` | `inboundpayments_create` |
| `voidTransaction(_:)` | `inboundpayments_void` |
| `readTransaction(_:)` | `inboundpayments_read` |
| `addCard`, `addBankAccount`, `addPaymentMethod` | `tokens_create` |

## Before you start

### Choose the form or your own UI

- **The SDK's form** keeps the card number inside SDK-owned state. It isn't written into a text field's
  `text`, an accessibility value or a callback, so your code never handles a card number.
- **Your own UI** passes `PayabliPayInCardData` you collected to the direct API. Your app then handles card
  numbers and security codes, which brings it into scope for PCI DSS.

## Set up

`PayabliPayIn` runs on the session `PayabliSession.initialize` returned. It is `@MainActor`.

```swift
import PayabliSDKCore
import PayabliSDKPayIn

let session = try await PayabliSession.initialize(config: PayabliConfig(
    entryPoint: "your-entry-point",
    environment: .sandbox,
    tokenProvider: { try await fetchPayabliAccessToken() }
))
let payIn = PayabliPayIn(
    session: session,
    operation: .capture,
    requestConfiguration: PayabliPayInRequestConfiguration(
        paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34),
        orderId: order.id // your own reference, to find the payment if its outcome is unknown
    )
)
```

A form that captures or authorizes needs this `PayabliPayInRequestConfiguration`. A direct call takes a
`PayabliPayInRequest` instead.

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
        paymentMethod: .card(.init(data: PayabliPayInCardData(
            cardNumber: "4012000098765439",
            expiration: "12/30",
            cardholderName: "Jane Doe",
            cvv: "999",
            billingZip: "12345"
        ))),
        options: PayabliPayInRequestConfiguration(
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34),
            orderId: order.id
        )
    )
)
order.paymentTransId = result.transaction?.paymentTransId // store it; don't log it
```

In sandbox, use Payabli's [test cards](https://docs.payabli.com/guides/test-accounts-reference).

### Store a payment method and charge it later

`addCard(_:options:)`, `addBankAccount(_:options:)` and `addPaymentMethod(_:options:)` save a method and
return a `PayabliPayInStoredPaymentMethod`. The form does the same with `.storePaymentMethod`. Its
`storedMethodId` is optional, and is `nil` when the service's answer names no ID. To charge a saved
method, pass `.stored(.init(method: .card, storedMethodId: id))` as the payment method.

### Authorize, then capture

`authorize(_:)` holds an amount on a card, a stored card or a cloud device without charging it. The form
authorizes a card only. `captureAuthorizedTransaction(_:)` captures that authorization later, and `voidTransaction(_:)`
releases it or voids a transaction that hasn't settled.

### Retry safely

A charge always sends an idempotency key, which the SDK makes and keeps; your app never handles one. Name each
payment with `paymentReference` on the request's options, or leave it unset and the SDK names the payment. The
reference stays on the device. Calling again is a new payment unless you say otherwise.

When a charge ends in `submissionInterrupted`, its outcome is unknown. The error carries the payment's
`paymentReference` and, when the service named one, its `paymentTransId`. Find the transaction first. If you charge
again, set `attempt: .retry` and that `paymentReference` on the options: the SDK sends that payment's key, so the
service refuses a repeat while it still recognises the key. When it refuses one, the charge ends in
`submissionInterrupted` with type `.retryRefused`, which means the earlier attempt reached the service. A refusal that
names an earlier payment matching this one ends with type `.conflict`. `captureAuthorizedTransaction(_:)` and
`voidTransaction(_:)` do this for their transaction without being asked.

A retry describes the same payment as the attempt it repeats: the same amount, fee, surcharge, currency, kind of
payment method and, if the first attempt set one, order identifier. A retry that describes another payment is refused
before anything is sent, with type `.retryNotSamePayment`, and the earlier attempt's key stays for the right
retry. A new payment that names a reference whose payment is still unresolved is refused before anything is sent,
with type `.paymentReferenceOpen`. A blank reference is refused as invalid input.

The SDK holds a payment's key in memory, on the `PayabliPayIn` it was sent from, for a few minutes after its latest
send, and holds at most 16 at a time. A retry after that, from another `PayabliPayIn`, or after your app restarts
sends a new key, so a reference you keep is a name and not a guard against a second charge. Past that point, read
the transaction back instead.

## Outcomes and errors

A returned result means what the call did, which depends on the call:

| Call | A result means | `transactionFailed` means |
|---|---|---|
| `capture(_:)` | The payment was charged | Not charged |
| `authorize(_:)` | An amount is held. Nothing is charged until you capture it | No hold was placed |
| `captureAuthorizedTransaction(_:)` | The held amount was charged | The hold wasn't captured |
| `voidTransaction(_:)` | The transaction was voided | The void was refused. It doesn't mean the original payment wasn't charged |

The outcomes are the ones in the root README's [Handle the outcome](../../README.md#handle-the-outcome). For
`authorize(_:)`, `captureAuthorizedTransaction(_:)` and `voidTransaction(_:)`, read "charged" as "held",
"captured" or "voided":

| Result | Outcome | What to do |
|---|---|---|
| The call returns a `PayabliPayInResult` | Charged, or saved | Store the transaction ID or the stored method ID |
| `PayabliPayInError.transactionFailed`, for example a decline | Not charged | You can retry |
| `PayabliPayInError.invalidInput`, `.submissionInProgress` | Not charged; refused before anything was sent | Fix the input, or wait for the running submission |
| A core `PayabliError` whose `type` is `.tokenProviderFailed` | Not charged; your token provider failed | Fix the token provider |
| `PayabliPayInError.submissionInterrupted` | Unknown | Read the transaction back with `readTransaction(_:)` before charging again: pass its `paymentTransId` when it carries one. Otherwise, after `capture(_:)` or `authorize(_:)`, find the transaction by `orderId` in the Payabli portal. After `captureAuthorizedTransaction(_:)` or `voidTransaction(_:)`, read back the transaction ID you passed. Then decide whether to call again |
| A core `PayabliError`, such as a validation failure, a refused credential or a rate limit | On a charge, not charged; the service's answer | Branch on its `type` |
| `PayabliPayInTokenStorageError` | The method wasn't saved | `invalidInput` was refused before sending; `saveFailed` is the service refusing it, typed `.paymentDeclined`. A failed status arrives as the core `PayabliError` for that status instead, and a 400 is `.validation` with the service's explanation in `detail` |
| A core `PayabliError` from `addCard`, `addBankAccount` or `addPaymentMethod` whose `type` is `.networkError`, `.serverError` or `.decodingError` | Unknown: the method may have been saved | Read the stored methods back before saving again |

Don't show `error.localizedDescription` to the payer or log it: it names what the service rejected and can
quote what was submitted. Show the payer a message for the error's `category`, and log
`(error as? any PayabliError)?.code`. Check for `submissionInterrupted` first: it keeps its cause's category, so a
retried payment refused for a rate limit or a credential is still one that may have gone through, and its message says so.

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
| `capture(_:)` | Charges a card, bank account, stored payment method, cloud device, check or cash |
| `authorize(_:)` | Authorizes a card, a stored card or a cloud device |
| `captureAuthorizedTransaction(_:)` | Captures an earlier authorization |
| `voidTransaction(_:)` | Voids a transaction that hasn't settled |
| `readTransaction(_:)` | Reads a transaction back and returns its `status`. A failure of type `TRANSACTION_NOT_FOUND` means nothing is visible under that ID yet, which isn't proof no payment was made: read again later rather than charging again |
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

Capture and authorize forms add a summary section with the amount and fee. A form storing a payment method
leaves it out. A summary section with no title is headed "Payment"; an inputs section with no title has no
heading.

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
