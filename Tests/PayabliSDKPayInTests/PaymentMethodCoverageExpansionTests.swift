@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import SwiftUI
import UIKit
import XCTest

final class PaymentMethodCoverageExpansionTests: XCTestCase {
    func testModuleVersionIsTheCoreVersion() {
        XCTAssertEqual(PayabliPayInModule.version, PayabliCore.version)
    }

    func testPaymentMethodTypeIdentifiersAndDisplayNames() {
        XCTAssertEqual(PayabliPayInMethodType.card.id, "card")
        XCTAssertEqual(PayabliPayInMethodType.card.displayName, "Card")
        XCTAssertEqual(PayabliPayInMethodType.bankAccount.id, "ach")
        XCTAssertEqual(PayabliPayInMethodType.bankAccount.displayName, "Bank account")
        XCTAssertEqual(PayabliPayInCardBrand.visa.id, "visa")
        XCTAssertEqual(PayabliPayInCardBrand.detect(cardNumber: "1"), .unknown)
        XCTAssertEqual(PayabliPayInAccountType.checking.id, "Checking")
        XCTAssertEqual(PayabliPayInAccountHolderType.business.id, "business")
        XCTAssertEqual(PayabliPayInSecCode.web.id, "WEB")
    }

    func testPaymentMethodInputReportsMethod() {
        let card = PayabliPayInMethodInput.card(PayabliPayInCardData(
            cardNumber: "4111111111111111",
            expiryMonth: 2,
            expiryYear: 2028,
            securityCode: "123",
            holderName: "Jane Doe",
            postalCode: "33139"
        ))
        let ach = PayabliPayInMethodInput.bankAccount(PayabliPayInBankAccountData(
            accountNumber: "1111111111",
            routingNumber: "123456780",
            accountType: .checking,
            holderName: "Jane Doe"
        ))

        XCTAssertEqual(card.method, .card)
        XCTAssertEqual(ach.method, .bankAccount)
    }

    func testPaymentMethodErrorMetadataAndValidationBranches() throws {
        let detailedFailure = PayabliPayInTokenStorageAPIResponse(
            isSuccess: false,
            responseText: "Gateway response",
            responseData: PayabliPayInTokenStorageAPIResponseData(
                explanation: "Gateway declined",
                todoAction: "Use another account."
            )
        ).failure(httpStatusCode: nil)
        let refused = PayabliPayInError.Refused(failure: detailedFailure)

        XCTAssertEqual(refused.type, .paymentDeclined)
        XCTAssertEqual(refused.reason, "Gateway declined")
        XCTAssertEqual(refused.detail, "Use another account.")

        XCTAssertThrowsError(try PayabliPayInCardData(
            cardNumber: "4111111111111111",
            expiryMonth: 13,
            expiryYear: 2028,
            securityCode: "123",
            holderName: "Jane Doe",
            postalCode: "33139"
        ).validate(PayabliPayInValidation(requiresLuhnCheck: false)))

        try PayabliPayInBankAccountData(
            accountNumber: "1111111111",
            routingNumber: "123456789",
            accountType: .checking,
            holderName: "Jane Doe"
        ).validate(PayabliPayInValidation(validatesRoutingNumberChecksum: false))

        XCTAssertThrowsError(try PayabliPayInBankAccountData(
            accountNumber: "1111111111",
            routingNumber: "123456789",
            accountType: .checking,
            holderName: "Jane Doe"
        ).validate(.default)) { error in
            guard let refusal = error as? PayabliPayInError.InvalidInput else {
                XCTFail("Expected invalid input error")
                return
            }
            XCTAssertEqual(refusal.reason, "Routing number failed validation.")
            XCTAssertEqual(refusal.field, "paymentMethod.achRouting")
        }

        XCTAssertThrowsError(try PayabliPayInBankAccountData(
            accountNumber: "1111111111",
            routingNumber: "123456789",
            accountType: .checking,
            holderName: " "
        ).validate(PayabliPayInValidation(validatesRoutingNumberChecksum: false))) { error in
            guard let refusal = error as? PayabliPayInError.InvalidInput else {
                XCTFail("Expected invalid input error")
                return
            }
            XCTAssertEqual(refusal.reason, "Account holder is required.")
            XCTAssertEqual(refusal.field, "paymentMethod.achHolder")
        }

        XCTAssertThrowsError(try PayabliPayInBankAccountData(
            accountNumber: "1111111111",
            routingNumber: "123456780",
            accountType: .checking,
            holderName: "Jane 🚀"
        ).validate(.default))
    }

    func testTheStoreBodySendsWEBAndNoDevice() throws {
        let input = PayabliPayInMethodInput.bankAccount(PayabliPayInBankAccountData(
            accountNumber: "1111111111",
            routingNumber: "123456780",
            accountType: .checking,
            holderName: "Jane Doe"
        ))

        let data = try Data(PayInBodyWriter.storeFragment(input).rawCopy())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["achCode"] as? String, "WEB")
        XCTAssertNil(object["device"])
    }

    func testPaymentMethodAPIResponseDecodesStringNumbers() throws {
        let data = Data("""
        {
          "isSuccess": true,
          "responseText": "Success",
          "responseCode": "200",
          "responseData": {
            "referenceId": "stored-123",
            "resultCode": "1",
            "customerId": "4440",
            "methodReferenceId": "method-123"
          }
        }
        """.utf8)

        let response = try JSONDecoder().decode(PayabliPayInTokenStorageAPIResponse.self, from: data)

        XCTAssertEqual(response.responseCode, 200)
        XCTAssertEqual(response.responseData?.resultCode, 1)
        XCTAssertEqual(response.responseData?.customerId, 4440)
    }

    func testAStoredMethodResultCarriesNoServiceText() {
        let storedMethod = PayabliPayInStoredMethod(
            storedMethodId: "stored-123",
            method: .card,
            methodReferenceId: "method-123",
            customerId: 4440
        )

        let result = PayabliPayInResult(storedPaymentMethod: storedMethod)

        XCTAssertEqual(result.code, "1")
        XCTAssertNil(result.reason)
        XCTAssertEqual(result.storedPaymentMethod, storedMethod)
    }

    func testPaymentMethodFailureFallbackReasonUsesResponseText() {
        let failure = PayabliPayInTokenStorageAPIResponse(isSuccess: false, responseText: "Gateway declined")
            .failure(httpStatusCode: nil)

        XCTAssertEqual(PayabliPayInError.Refused(failure: failure).reason, "Gateway declined")
    }

    func testSheetDismissButtonMetadata() {
        XCTAssertEqual(PayabliPayInSheetDismissButton.close.systemImageName, "xmark")
        XCTAssertEqual(PayabliPayInSheetDismissButton.close.accessibilityLabel, "Close")
        XCTAssertEqual(PayabliPayInSheetDismissButton.back.systemImageName, "chevron.left")
        XCTAssertEqual(PayabliPayInSheetDismissButton.back.accessibilityLabel, "Back")
        XCTAssertNil(PayabliPayInSheetDismissButton.hidden.systemImageName)
        XCTAssertEqual(PayabliPayInSheetDismissButton.hidden.accessibilityLabel, "")
    }

    @MainActor
    func testPaymentMethodSheetModifierPresents() {
        let component = flowOnSession(
            token: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let rootView = PaymentMethodSheetHarness(
            payIn: component,
            operation: .storePaymentMethod(),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card]),
            labels: PayabliPayInFormLabels(title: "Inline title", subtitle: "Inline subtitle"),
            sheetConfiguration: PayabliPayInSheetConfiguration(
                title: "Sheet title",
                subtitle: "Sheet subtitle",
                dismissButton: .back,
                detents: [.medium, .large],
                movesFormHeaderToSheetHeader: true
            )
        )
        let host = UIHostingController(rootView: rootView)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()

        PayInUIKitHostingSupport.waitForPresentedViewController(from: host)

        XCTAssertNotNil(host.presentedViewController)
    }

    @MainActor
    func testPaymentMethodSheetContentRendersFormFields() {
        var isPresented = true
        let component = flowOnSession(
            token: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let view = PayabliPayInSheetContent(
            isPresented: Binding(get: { isPresented }, set: { isPresented = $0 }),
            payIn: component,
            operation: .storePaymentMethod(),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card]),
            labels: PayabliPayInFormLabels(title: "Inline title", subtitle: "Inline subtitle"),
            sheetConfiguration: PayabliPayInSheetConfiguration(
                title: "Sheet title",
                subtitle: "Sheet subtitle",
                dismissButton: .back,
                detents: [.large],
                movesFormHeaderToSheetHeader: true
            ),
            style: nil,
            onCompleted: { _ in },
            onFailed: { _ in },
            onMethodChanged: { _ in }
        )
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()

        PayInUIKitHostingSupport.waitForRenderedSubviews(in: host.view)
        let textFields = host.view.payabliCoverageAllSubviews.compactMap { $0 as? UITextField }
        XCTAssertTrue(textFields.contains { $0.accessibilityLabel == "Card number" })
    }

    @MainActor
    func testPaymentMethodSheetContentRendersInlineHeaderWhenSheetHeaderIsHidden() {
        var isPresented = true
        let component = flowOnSession(
            token: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let view = PayabliPayInSheetContent(
            isPresented: Binding(get: { isPresented }, set: { isPresented = $0 }),
            payIn: component,
            operation: .storePaymentMethod(),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card]),
            labels: PayabliPayInFormLabels(
                title: "Inline card form",
                subtitle: "Inline subtitle"
            ),
            sheetConfiguration: PayabliPayInSheetConfiguration(
                dismissButton: .hidden,
                detents: [.height(360)],
                movesFormHeaderToSheetHeader: false,
                sizesToContentWhenPossible: false,
                expandsToLargeWhenContentDoesNotFit: false
            ),
            style: nil,
            onCompleted: { _ in },
            onFailed: { _ in },
            onMethodChanged: { _ in }
        )
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()

        PayInUIKitHostingSupport.waitForRenderedSubviews(in: host.view)
        let textFields = host.view.payabliCoverageAllSubviews.compactMap { $0 as? UITextField }

        XCTAssertTrue(textFields.contains { $0.accessibilityLabel == "Card number" })
    }

    @MainActor
    func testTheSheetsOwnWordingWinsWhenBothSupplyIt() {
        let content = sheetContent(movingHeader: true, sheetTitle: "Sheet title", sheetSubtitle: "Sheet subtitle")

        XCTAssertEqual(content.sheetTitle, "Sheet title")
        XCTAssertEqual(content.sheetSubtitle, "Sheet subtitle")
        XCTAssertNil(content.formLabels.title, "the form draws no heading of its own")
        XCTAssertNil(content.formLabels.subtitle, "the form draws no subtitle of its own")
    }

    @MainActor
    func testTheFormsWordingMovesUpWhenTheSheetSuppliesNoneOfItsOwn() {
        let content = sheetContent(movingHeader: true, sheetTitle: nil, sheetSubtitle: nil)

        XCTAssertEqual(content.sheetTitle, "Inline title")
        XCTAssertEqual(content.sheetSubtitle, "Inline subtitle")
        XCTAssertNil(content.formLabels.title, "the heading was moved, not copied")
    }

    @MainActor
    func testTheFormKeepsItsWordingWhenTheHeaderMoveIsOff() {
        let content = sheetContent(movingHeader: false, sheetTitle: "Sheet title", sheetSubtitle: "Sheet subtitle")

        XCTAssertEqual(content.sheetTitle, "Sheet title")
        XCTAssertEqual(content.sheetSubtitle, "Sheet subtitle")
        XCTAssertEqual(content.formLabels.title, "Inline title", "the form keeps its own heading")
        XCTAssertEqual(content.formLabels.subtitle, "Inline subtitle")
    }

    @MainActor
    func testABlankSheetTitleCountsAsUnsupplied() {
        let content = sheetContent(movingHeader: true, sheetTitle: "   ", sheetSubtitle: nil)

        XCTAssertEqual(content.sheetTitle, "Inline title")
    }

    /// A sheet content whose form supplies its own wording, with the header move as given.
    @MainActor
    private func sheetContent(
        movingHeader: Bool,
        sheetTitle: String?,
        sheetSubtitle: String?
    ) -> PayabliPayInSheetContent {
        PayabliPayInSheetContent(
            isPresented: .constant(true),
            payIn: flowOnSession(),
            operation: .storePaymentMethod(),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card]),
            labels: PayabliPayInFormLabels(title: "Inline title", subtitle: "Inline subtitle"),
            sheetConfiguration: PayabliPayInSheetConfiguration(
                title: sheetTitle,
                subtitle: sheetSubtitle,
                movesFormHeaderToSheetHeader: movingHeader
            ),
            style: nil,
            onCompleted: { _ in },
            onFailed: { _ in },
            onMethodChanged: { _ in }
        )
    }

    @MainActor
    func testHostedACHFormRendersAccountPickerAndCustomerFields() {
        let component = flowOnSession(
            token: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let view = PayabliPayInForm(
            payIn: component,
            operation: .storePaymentMethod(),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.bankAccount],
                defaultMethod: .bankAccount,
                requiredFields: [
                    .firstName,
                    .lastName,
                    .customerNumber,
                    .billingEmail,
                    .billingPostalCode
                ]
            ),
            onCompleted: { _ in },
            onFailed: { _ in },
            onMethodChanged: { _ in }
        )
        let host = PayInUIKitHostingSupport.host(view)

        PayInUIKitHostingSupport.waitForRenderedSubviews(in: host.view)
        let textFields = host.view.payabliCoverageAllSubviews.compactMap { $0 as? UITextField }
        let labels = Set(textFields.compactMap(\.accessibilityLabel))

        XCTAssertTrue(labels.contains("Account holder"))
        XCTAssertTrue(labels.contains("Routing number"))
        XCTAssertTrue(labels.contains("Account number"))
        XCTAssertFalse(labels.contains("Description"), "the form drew a description field")
        XCTAssertTrue(labels.contains("Billing email"))
    }

    @MainActor
    func testHostedACHFormRendersPlaceholderSectionsAndUnmaskedAccount() throws {
        let component = flowOnSession(
            token: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let view = PayabliPayInForm(
            payIn: component,
            operation: .storePaymentMethod(),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.bankAccount],
                defaultMethod: .bankAccount,
                bankSections: [
                    PayabliPayInFieldSection(
                        title: "Bank Information",
                        fields: [.accountHolder, .routingNumber, .accountNumber, .accountType, .accountHolderType],
                        inputVerticalSpacing: 2,
                        inputHorizontalSpacing: 4,
                        fieldVerticalSpacings: [.accountHolder: 1]
                    ),
                    PayabliPayInFieldSection(
                        title: "Customer Information",
                        fields: [.firstName, .lastName, .billingEmail]
                    )
                ],
                labelLayout: .placeholder,
                formatting: PayabliPayInFormatting(masksAccountNumber: false),
                requiredFields: [.firstName, .lastName, .billingEmail]
            ),
            labels: PayabliPayInFormLabels(
                title: "Bank account form",
                subtitle: "Collect bank details"
            ),
            onCompleted: { _ in },
            onFailed: { _ in },
            onMethodChanged: { _ in }
        )
        .environment(\.dynamicTypeSize, .accessibility1)
        let host = PayInUIKitHostingSupport.host(view)

        PayInUIKitHostingSupport.waitForRenderedSubviews(in: host.view)
        let textFields = host.view.payabliCoverageAllSubviews.compactMap { $0 as? UITextField }
        let accountField = try XCTUnwrap(textFields.first { $0.accessibilityLabel == "Account number" })
        let holderField = try XCTUnwrap(textFields.first { $0.accessibilityLabel == "Account holder" })

        XCTAssertFalse(accountField.isSecureTextEntry)
        XCTAssertEqual(holderField.attributedPlaceholder?.string, "Account holder")
    }

    @MainActor
    func testHostedCombinedFormRendersMethodSelectorAndCardValidationError() throws {
        let component = flowOnSession(
            token: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let view = PayabliPayInForm(
            payIn: component,
            operation: .storePaymentMethod(),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.card, .bankAccount],
                cardBrandIconPlacement: .leading
            ),
            onCompleted: { _ in },
            onFailed: { _ in },
            onMethodChanged: { _ in }
        )
        let host = PayInUIKitHostingSupport.host(view)

        PayInUIKitHostingSupport.waitForRenderedSubviews(in: host.view)
        let cardNumberField = try XCTUnwrap(
            host.view.payabliCoverageAllSubviews
                .compactMap { $0 as? UITextField }
                .first { $0.accessibilityLabel == "Card number" }
        )
        cardNumberField.text = "4111111111111112"
        _ = cardNumberField.delegate?.textField?(
            cardNumberField,
            shouldChangeCharactersIn: NSRange(location: 0, length: 0),
            replacementString: "4111111111111112"
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertEqual(cardNumberField.accessibilityLabel, "Card number")
    }

    @MainActor
    func testHostedCardEntryMasksPANFromHostVisibleTextAndAccessibility() throws {
        let component = flowOnSession(
            token: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let view = PayabliPayInForm(
            payIn: component,
            operation: .storePaymentMethod(),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card]),
            onCompleted: { _ in },
            onFailed: { _ in },
            onMethodChanged: { _ in }
        )
        let host = PayInUIKitHostingSupport.host(view)

        PayInUIKitHostingSupport.waitForRenderedSubviews(in: host.view)
        let cardNumberField = try XCTUnwrap(
            host.view.payabliCoverageAllSubviews
                .compactMap { $0 as? UITextField }
                .first { $0.accessibilityLabel == "Card number" }
        )

        _ = cardNumberField.delegate?.textField?(
            cardNumberField,
            shouldChangeCharactersIn: NSRange(location: 0, length: 0),
            replacementString: "4111111111111111"
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertEqual(cardNumberField.text, "•••• •••• •••• 1111")
        XCTAssertFalse(cardNumberField.text?.contains("4111111111111111") == true)
        XCTAssertFalse(cardNumberField.text?.contains("4111 1111 1111 1111") == true)
        XCTAssertEqual(cardNumberField.accessibilityValue, "Entered")
    }

    @MainActor
    func testPaymentMethodConvenienceInitializersAndSubmitHelpers() async throws {
        let transport = CoverageTransport(responseBody: """
        {
          "responseText": "Success",
          "isSuccess": true,
          "responseData": {
            "referenceId": "stored-123",
            "resultCode": 1,
            "resultText": "Approved"
          }
        }
        """)
        let component = PayabliPayIn(entryPoint: "entry", environment: .sandbox, transport: transport)

        let cardResult = try await component.storeMethod(PayabliPayInStoreRequest(
            instrument: .card(PayabliPayInCardData(
                cardNumber: "4111111111111111",
                expiryMonth: 2,
                expiryYear: 2028,
                securityCode: "123",
                holderName: "Jane Doe",
                postalCode: "33139"
            )),
            options: PayabliPayInStoreOptions()
        ))
        let achResult = try await component.storeMethod(PayabliPayInStoreRequest(
            instrument: .bankAccount(PayabliPayInBankAccountData(
                accountNumber: "1111111111",
                routingNumber: "123456780",
                accountType: .checking,
                holderName: "Jane Doe"
            )),
            options: PayabliPayInStoreOptions()
        ))

        XCTAssertEqual(cardResult.storedMethodId, "stored-123")
        XCTAssertEqual(achResult.storedMethodId, "stored-123")
        XCTAssertEqual(component.lastStoredPaymentMethod?.storedMethodId, "stored-123")
        let requestCount = await transport.capturedRequestCount()
        XCTAssertEqual(requestCount, 2)
    }

    @MainActor
    func testHostedUIKitTextFieldUpdateSanitizesInitialTextAndAppliesMetadata() throws {
        let host = PayInUIKitHostingSupport.host(UIKitTextFieldSanitizingHarness())

        PayInUIKitHostingSupport.waitForRenderedSubviews(in: host.view)
        let textField = try XCTUnwrap(
            host.view.payabliCoverageAllSubviews
                .compactMap { $0 as? UITextField }
                .first { $0.accessibilityLabel == "Hosted card number" }
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))

        XCTAssertEqual(textField.text, "12")
        XCTAssertEqual(textField.keyboardType, .numberPad)
        XCTAssertEqual(textField.textContentType, .creditCardNumber)
        XCTAssertEqual(textField.autocapitalizationType, .none)
        XCTAssertEqual(textField.isSecureTextEntry, false)
        XCTAssertEqual(textField.accessibilityHint, "Digits only")
        XCTAssertEqual(
            textField.accessibilityIdentifier,
            PayabliPayInAccessibility.fieldIdentifier(.cardNumber)
        )
        XCTAssertEqual(textField.accessibilityValue, "12")
        XCTAssertEqual(textField.attributedPlaceholder?.string, "Hosted card number")
    }

    /// The form disables its UIKit fields while a submission is in flight, end to end. Current runtimes
    /// carry a container's disabled state into the wrapped view themselves, so this cannot tell the
    /// representable's own application from the framework's; the helper test asserts that directly.
    @MainActor
    func testADisabledContainerMakesTheUIKitFieldRefuseInputAndDropTheKeyboard() throws {
        let store = UIKitTextFieldDisableStore()
        let host = PayInUIKitHostingSupport.host(UIKitTextFieldDisableHarness(store: store))

        PayInUIKitHostingSupport.waitForRenderedSubviews(in: host.view)
        let textField = try XCTUnwrap(
            host.view.payabliCoverageAllSubviews
                .compactMap { $0 as? UITextField }
                .first { $0.accessibilityLabel == "Hosted card number" }
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))

        XCTAssertTrue(textField.isEnabled)
        XCTAssertTrue(textField.becomeFirstResponder())
        XCTAssertTrue(textField.isFirstResponder)

        store.disabled = true
        waitForDisabledField(in: host.view, textField)

        XCTAssertFalse(textField.isEnabled)
        XCTAssertFalse(textField.isFirstResponder)
    }

    @MainActor
    private func waitForDisabledField(
        in view: UIView,
        _ textField: UITextField,
        timeout: TimeInterval = 1
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while textField.isEnabled || textField.isFirstResponder, Date() < deadline {
            view.setNeedsLayout()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }
}

private struct PaymentMethodSheetHarness: View {
    @State private var isPresented = true

    let payIn: PayabliPayIn
    let operation: PayabliPayInOperation
    let configuration: PayabliPayInFormConfiguration
    let labels: PayabliPayInFormLabels
    let sheetConfiguration: PayabliPayInSheetConfiguration

    var body: some View {
        Text("Host")
            .payabliPayInSheet(
                isPresented: $isPresented,
                payIn: payIn,
                operation: operation,
                configuration: configuration,
                labels: labels,
                sheetConfiguration: sheetConfiguration,
                onCompleted: { _ in },
                onFailed: { _ in },
                onMethodChanged: { _ in }
            )
    }
}

private struct UIKitTextFieldSanitizingHarness: View {
    @State private var text = "12ab"
    @State private var focusedField: PayabliPayInField?

    var body: some View {
        PayabliPayInUIKitTextField(
            text: $text,
            placeholder: "Hosted card number",
            field: .cardNumber,
            focusedField: $focusedField,
            keyboardType: .numberPad,
            textContentType: .creditCardNumber,
            autocapitalization: .none,
            isSecure: false,
            font: UIFont.systemFont(ofSize: 18),
            textColor: .systemRed,
            placeholderColor: .systemBlue,
            accessibilityLabel: "Hosted card number",
            accessibilityHint: "Digits only",
            sanitize: \.digitsOnly
        )
        .frame(width: 240, height: 44)
    }
}

@MainActor
private final class UIKitTextFieldDisableStore: ObservableObject {
    @Published var disabled = false
}

private struct UIKitTextFieldDisableHarness: View {
    @ObservedObject var store: UIKitTextFieldDisableStore
    @State private var text = ""
    @State private var focusedField: PayabliPayInField?

    var body: some View {
        PayabliPayInUIKitTextField(
            text: $text,
            placeholder: "Hosted card number",
            field: .cardNumber,
            focusedField: $focusedField,
            keyboardType: .numberPad,
            accessibilityLabel: "Hosted card number"
        )
        .disabled(store.disabled)
        .frame(width: 240, height: 44)
    }
}

private actor CoverageTransport: PayabliTransport {
    private let responseBody: String
    private(set) var requestCount = 0

    init(responseBody: String) {
        self.responseBody = responseBody
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        requestCount += 1
        return PayabliResponse(
            statusCode: 200,
            headers: [:],
            body: Data(responseBody.utf8)
        )
    }

    func capturedRequestCount() -> Int {
        requestCount
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        throw PayabliGenericError(type: .unknown, reason: "performV2 is not used")
    }
}
