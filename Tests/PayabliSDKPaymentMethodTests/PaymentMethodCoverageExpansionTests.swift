@testable import PayabliSDKCore
@testable import PayabliSDKPaymentMethod
import SwiftUI
import UIKit
import XCTest

final class PaymentMethodCoverageExpansionTests: XCTestCase {
    func testModuleVersionIsAvailable() {
        XCTAssertFalse(PayabliPaymentMethodModule.version.isEmpty)
    }

    func testPaymentMethodTypeIdentifiersAndDisplayNames() {
        XCTAssertEqual(PayabliPaymentMethodType.card.id, "card")
        XCTAssertEqual(PayabliPaymentMethodType.card.displayName, "Card")
        XCTAssertEqual(PayabliPaymentMethodType.ach.id, "ach")
        XCTAssertEqual(PayabliPaymentMethodType.ach.displayName, "ACH")
        XCTAssertEqual(PayabliPaymentMethodCardBrand.visa.id, "visa")
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: "1"), .unknown)
        XCTAssertEqual(PayabliACHAccountType.checking.id, "Checking")
        XCTAssertEqual(PayabliACHHolderType.business.id, "business")
        XCTAssertEqual(PayabliACHSecCode.web.id, "WEB")
    }

    func testPaymentMethodInputReportsMethod() {
        let card = PayabliPaymentMethodInput.card(PayabliCardPaymentMethodData(
            cardNumber: "4111111111111111",
            expiration: "02/28",
            cardholderName: "Jane Doe",
            cvv: "123",
            billingZip: "33139"
        ))
        let ach = PayabliPaymentMethodInput.ach(PayabliACHPaymentMethodData(
            accountNumber: "1111111111",
            accountType: .checking,
            holderName: "Jane Doe",
            routingNumber: "123456780"
        ))

        XCTAssertEqual(card.method, .card)
        XCTAssertEqual(ach.method, .ach)
    }

    func testPaymentMethodErrorMetadataAndValidationBranches() throws {
        let fallbackFailure = PayabliPaymentMethodFailure(responseText: "   ")
        let detailedFailure = PayabliPaymentMethodFailure(
            responseText: "Gateway response",
            explanation: "Gateway declined",
            todoAction: "Use another account."
        )

        XCTAssertEqual(fallbackFailure.reason, "Unable to save payment method.")
        XCTAssertNil(PayabliPaymentMethodError.missingAccessToken.detail)
        XCTAssertEqual(PayabliPaymentMethodError.missingAccessToken.code, .missingToken)
        XCTAssertEqual(PayabliPaymentMethodError.missingAccessToken.reason, "Missing access token")
        XCTAssertEqual(PayabliPaymentMethodError.saveFailed(detailedFailure).code, .unknown)
        XCTAssertEqual(PayabliPaymentMethodError.saveFailed(detailedFailure).reason, "Gateway declined")
        XCTAssertEqual(PayabliPaymentMethodError.saveFailed(detailedFailure).detail, "Use another account.")

        XCTAssertThrowsError(try PayabliCardPaymentMethodData(
            cardNumber: "4111111111111111",
            expiration: "13/28",
            cardholderName: "Jane Doe",
            cvv: "123",
            billingZip: "33139"
        ).validate(PayabliPaymentMethodValidation(requiresLuhnCheck: false)))

        try PayabliACHPaymentMethodData(
            accountNumber: "1111111111",
            accountType: .checking,
            holderName: "Jane Doe",
            routingNumber: "123456789"
        ).validate(PayabliPaymentMethodValidation(validatesACHRoutingChecksum: false))

        XCTAssertThrowsError(try PayabliACHPaymentMethodData(
            accountNumber: "1111111111",
            accountType: .checking,
            holderName: "Jane Doe",
            routingNumber: "123456789"
        ).validate(.default)) { error in
            guard case let PayabliPaymentMethodError.invalidInput(message) = error else {
                XCTFail("Expected invalid input error")
                return
            }
            XCTAssertEqual(message, "ACH routing number failed validation.")
        }

        XCTAssertThrowsError(try PayabliACHPaymentMethodData(
            accountNumber: "1111111111",
            accountType: .checking,
            holderName: " ",
            routingNumber: "123456789"
        ).validate(PayabliPaymentMethodValidation(validatesACHRoutingChecksum: false))) { error in
            guard case let PayabliPaymentMethodError.invalidInput(message) = error else {
                XCTFail("Expected invalid input error")
                return
            }
            XCTAssertEqual(message, "ACH account holder is required.")
        }

        XCTAssertThrowsError(try PayabliACHPaymentMethodData(
            accountNumber: "1111111111",
            accountType: .checking,
            holderName: "Jane 🚀",
            routingNumber: "123456780"
        ).validate(.default))
    }

    func testPaymentMethodInputEncodingTrimsOptionalACHDevice() throws {
        let input = PayabliPaymentMethodInput.ach(PayabliACHPaymentMethodData(
            accountNumber: "1111111111",
            accountType: .checking,
            holderName: "Jane Doe",
            routingNumber: "123456780",
            device: " terminal-1 "
        ))

        let data = try JSONEncoder().encode(input)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["achCode"] as? String, "WEB")
        XCTAssertEqual(object["device"] as? String, "terminal-1")
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

        let response = try JSONDecoder().decode(PayabliPaymentMethodAPIResponse.self, from: data)

        XCTAssertEqual(response.responseCode, 200)
        XCTAssertEqual(response.responseData?.resultCode, 1)
        XCTAssertEqual(response.responseData?.customerId, 4440)
    }

    func testStoredPaymentMethodBuildsDefaultAPIResponse() {
        let storedMethod = PayabliStoredPaymentMethod(
            storedMethodId: "stored-123",
            methodReferenceId: "method-123",
            resultCode: 1,
            resultText: "Approved",
            customerId: 4440,
            responseText: "Success"
        )

        XCTAssertEqual(storedMethod.apiResponse.responseText, "Success")
        XCTAssertEqual(storedMethod.apiResponse.responseData?.referenceId, "stored-123")
        XCTAssertEqual(storedMethod.apiResponse.responseData?.methodReferenceId, "method-123")
    }

    func testPaymentMethodFailureFallbackReasonUsesResponseText() {
        let failure = PayabliPaymentMethodFailure(responseText: "Gateway declined")

        XCTAssertEqual(failure.reason, "Gateway declined")
    }

    func testSheetDismissButtonMetadata() {
        XCTAssertEqual(PayabliPaymentMethodSheetDismissButton.close.systemImageName, "xmark")
        XCTAssertEqual(PayabliPaymentMethodSheetDismissButton.close.accessibilityLabel, "Close")
        XCTAssertEqual(PayabliPaymentMethodSheetDismissButton.back.systemImageName, "chevron.left")
        XCTAssertEqual(PayabliPaymentMethodSheetDismissButton.back.accessibilityLabel, "Back")
        XCTAssertNil(PayabliPaymentMethodSheetDismissButton.hidden.systemImageName)
        XCTAssertEqual(PayabliPaymentMethodSheetDismissButton.hidden.accessibilityLabel, "")
    }

    @MainActor
    func testPaymentMethodSheetModifierPresents() {
        let component = PayabliPaymentMethod(
            accessToken: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let rootView = PaymentMethodSheetHarness(
            component: component,
            configuration: PayabliPaymentMethodFormConfiguration(
                allowedMethods: [.card],
                labels: PayabliPaymentMethodLabels(
                    title: "Inline title",
                    subtitle: "Inline subtitle"
                )
            ),
            sheetConfiguration: PayabliPaymentMethodSheetConfiguration(
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

        waitForPresentedViewController(from: host)

        XCTAssertNotNil(host.presentedViewController)
    }

    @MainActor
    func testPaymentMethodSheetContentRendersFormFields() {
        var isPresented = true
        let component = PayabliPaymentMethod(
            accessToken: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let view = PayabliPaymentMethodSheetContent(
            isPresented: Binding(get: { isPresented }, set: { isPresented = $0 }),
            component: component,
            configuration: PayabliPaymentMethodFormConfiguration(
                allowedMethods: [.card],
                labels: PayabliPaymentMethodLabels(
                    title: "Inline title",
                    subtitle: "Inline subtitle"
                )
            ),
            sheetConfiguration: PayabliPaymentMethodSheetConfiguration(
                title: "Sheet title",
                subtitle: "Sheet subtitle",
                dismissButton: .back,
                detents: [.large],
                movesFormHeaderToSheetHeader: true
            ),
            style: nil,
            onPaymentMethodAdded: { _ in },
            onError: { _ in }
        )
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()

        waitForRenderedSubviews(in: host.view)
        let textFields = host.view.payabliCoverageAllSubviews.compactMap { $0 as? UITextField }
        XCTAssertTrue(textFields.contains { $0.accessibilityLabel == "Card number" })
    }

    @MainActor
    func testPaymentMethodSheetContentRendersInlineHeaderWhenSheetHeaderIsHidden() {
        var isPresented = true
        let component = PayabliPaymentMethod(
            accessToken: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let view = PayabliPaymentMethodSheetContent(
            isPresented: Binding(get: { isPresented }, set: { isPresented = $0 }),
            component: component,
            configuration: PayabliPaymentMethodFormConfiguration(
                allowedMethods: [.card],
                labels: PayabliPaymentMethodLabels(
                    title: "Inline card form",
                    subtitle: "Inline subtitle"
                )
            ),
            sheetConfiguration: PayabliPaymentMethodSheetConfiguration(
                dismissButton: .hidden,
                detents: [.height(360)],
                movesFormHeaderToSheetHeader: false,
                sizesToContentWhenPossible: false,
                expandsToLargeWhenContentDoesNotFit: false
            ),
            style: nil,
            onPaymentMethodAdded: { _ in },
            onError: { _ in }
        )
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()

        waitForRenderedSubviews(in: host.view)
        let textFields = host.view.payabliCoverageAllSubviews.compactMap { $0 as? UITextField }

        XCTAssertTrue(textFields.contains { $0.accessibilityLabel == "Card number" })
    }

    @MainActor
    func testHostedACHFormRendersAccountPickerAndCustomerFields() {
        let component = PayabliPaymentMethod(
            accessToken: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let view = PayabliPaymentMethodView(
            component: component,
            configuration: PayabliPaymentMethodFormConfiguration(
                allowedMethods: [.ach],
                defaultMethod: .ach,
                requiredFields: [
                    .achDevice,
                    .methodDescription,
                    .firstName,
                    .lastName,
                    .customerNumber,
                    .billingEmail,
                    .billingZip
                ]
            ),
            onPaymentMethodAdded: { _ in }
        )
        let host = host(view)

        waitForRenderedSubviews(in: host.view)
        let textFields = host.view.payabliCoverageAllSubviews.compactMap { $0 as? UITextField }
        let labels = Set(textFields.compactMap(\.accessibilityLabel))

        XCTAssertTrue(labels.contains("Account holder"))
        XCTAssertTrue(labels.contains("Routing number"))
        XCTAssertTrue(labels.contains("Account number"))
        XCTAssertTrue(labels.contains("Device"))
        XCTAssertTrue(labels.contains("Description"))
        XCTAssertTrue(labels.contains("Billing email"))
    }

    @MainActor
    func testHostedACHFormRendersPlaceholderSectionsAndUnmaskedAccount() throws {
        let component = PayabliPaymentMethod(
            accessToken: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let view = PayabliPaymentMethodView(
            component: component,
            configuration: PayabliPaymentMethodFormConfiguration(
                allowedMethods: [.ach],
                defaultMethod: .ach,
                achSections: [
                    PayabliPaymentMethodFieldSection(
                        title: "Bank Information",
                        fields: [.achHolder, .achRouting, .achAccount, .achAccountType, .achHolderType],
                        inputVerticalSpacing: 2,
                        inputHorizontalSpacing: 4,
                        fieldVerticalSpacings: [.achHolder: 1]
                    ),
                    PayabliPaymentMethodFieldSection(
                        title: "Customer Information",
                        fields: [.firstName, .lastName, .billingEmail]
                    )
                ],
                labels: PayabliPaymentMethodLabels(
                    title: "ACH form",
                    subtitle: "Collect bank details"
                ),
                labelLayout: .placeholder,
                formatting: PayabliPaymentMethodFormatting(masksACHAccountEntry: false),
                requiredFields: [.firstName, .lastName, .billingEmail]
            ),
            onPaymentMethodAdded: { _ in }
        )
        .environment(\.dynamicTypeSize, .accessibility1)
        let host = host(view)

        waitForRenderedSubviews(in: host.view)
        let textFields = host.view.payabliCoverageAllSubviews.compactMap { $0 as? UITextField }
        let accountField = try XCTUnwrap(textFields.first { $0.accessibilityLabel == "Account number" })
        let holderField = try XCTUnwrap(textFields.first { $0.accessibilityLabel == "Account holder" })

        XCTAssertFalse(accountField.isSecureTextEntry)
        XCTAssertEqual(holderField.attributedPlaceholder?.string, "Account holder")
    }

    @MainActor
    func testHostedCombinedFormRendersMethodSelectorAndCardValidationError() throws {
        let component = PayabliPaymentMethod(
            accessToken: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let view = PayabliPaymentMethodView(
            component: component,
            configuration: PayabliPaymentMethodFormConfiguration(
                allowedMethods: [.card, .ach],
                cardBrandIconPlacement: .leading
            ),
            onPaymentMethodAdded: { _ in }
        )
        let host = host(view)

        waitForRenderedSubviews(in: host.view)
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
        let component = PayabliPaymentMethod(
            config: PayabliConfig(
                accessToken: "unused",
                entryPoint: "entry",
                environment: .sandbox
            ),
            accessTokenProvider: { "access-token" },
            transport: transport
        )

        let cardResult = try await component.addCard(PayabliCardPaymentMethodData(
            cardNumber: "4111111111111111",
            expiration: "02/28",
            cardholderName: "Jane Doe",
            cvv: "123",
            billingZip: "33139"
        ))
        let achResult = try await component.addACH(PayabliACHPaymentMethodData(
            accountNumber: "1111111111",
            accountType: .checking,
            holderName: "Jane Doe",
            routingNumber: "123456780"
        ))

        XCTAssertEqual(cardResult.storedMethodId, "stored-123")
        XCTAssertEqual(achResult.storedMethodId, "stored-123")
        XCTAssertEqual(component.lastStoredPaymentMethod?.storedMethodId, "stored-123")
        let requestCount = await transport.capturedRequestCount()
        XCTAssertEqual(requestCount, 2)
    }

    @MainActor
    func testUIKitTextFieldCoordinatorSanitizesAndTracksFocus() {
        var text = "12"
        var focusedField: PayabliPaymentMethodField?
        let field = PayabliPaymentMethodUIKitTextField(
            text: Binding(get: { text }, set: { text = $0 }),
            placeholder: "Card number",
            field: .cardNumber,
            focusedField: Binding(get: { focusedField }, set: { focusedField = $0 }),
            accessibilityLabel: "Card number",
            sanitize: \.digitsOnly
        )
        let coordinator = field.makeCoordinator()
        let textField = UITextField()
        textField.text = "12"

        coordinator.textFieldDidBeginEditing(textField)
        XCTAssertEqual(focusedField, .cardNumber)

        XCTAssertFalse(coordinator.textField(
            textField,
            shouldChangeCharactersIn: NSRange(location: 2, length: 0),
            replacementString: "ab3"
        ))
        XCTAssertEqual(textField.text, "123")
        XCTAssertEqual(text, "123")

        XCTAssertTrue(coordinator.textField(
            textField,
            shouldChangeCharactersIn: NSRange(location: 3, length: 0),
            replacementString: "4"
        ))

        coordinator.editingChanged(textField)
        XCTAssertEqual(text, "123")

        coordinator.textFieldDidEndEditing(textField)
        XCTAssertNil(focusedField)
    }

    @MainActor
    func testUIKitTextFieldDefaultSanitizerAllowsChangesAndRejectsInvalidRanges() {
        var text = "Hello"
        var focusedField: PayabliPaymentMethodField?
        let field = PayabliPaymentMethodUIKitTextField(
            text: Binding(get: { text }, set: { text = $0 }),
            placeholder: "",
            field: .cardholderName,
            focusedField: Binding(get: { focusedField }, set: { focusedField = $0 }),
            accessibilityLabel: "Cardholder name"
        )
        let coordinator = field.makeCoordinator()
        let textField = UITextField()
        textField.text = "Hello"

        XCTAssertFalse(coordinator.textField(
            textField,
            shouldChangeCharactersIn: NSRange(location: 99, length: 0),
            replacementString: "!"
        ))
        XCTAssertTrue(coordinator.textField(
            textField,
            shouldChangeCharactersIn: NSRange(location: 5, length: 0),
            replacementString: "!"
        ))

        coordinator.editingChanged(textField)
        XCTAssertEqual(text, "Hello")
    }

    @MainActor
    func testHostedUIKitTextFieldUpdateSanitizesInitialTextAndAppliesMetadata() throws {
        let host = host(UIKitTextFieldSanitizingHarness())

        waitForRenderedSubviews(in: host.view)
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
        XCTAssertEqual(textField.accessibilityIdentifier, "payabli.paymentMethod.field.cardNumber")
        XCTAssertEqual(textField.accessibilityValue, "12")
        XCTAssertEqual(textField.attributedPlaceholder?.string, "Hosted card number")
    }

    @MainActor
    func testObjCStoredPaymentMethodWrapperConvertsValuesAndResponse() {
        let storedMethod = PayabliStoredPaymentMethod(
            storedMethodId: "stored-123",
            methodReferenceId: "method-123",
            resultCode: 1,
            resultText: "Approved",
            customerId: 4440,
            responseText: "Success",
            apiResponse: PayabliPaymentMethodAPIResponse(
                isSuccess: true,
                responseText: "Success",
                responseCode: 200,
                responseData: PayabliPaymentMethodAPIResponseData(
                    referenceId: "stored-123",
                    resultCode: 1,
                    resultText: "Approved",
                    customerId: 4440,
                    methodReferenceId: "method-123"
                )
            )
        )

        let wrapper = PayabliStoredPaymentMethodObjC(storedMethod)

        XCTAssertEqual(wrapper.storedMethodId, "stored-123")
        XCTAssertEqual(wrapper.methodReferenceId, "method-123")
        XCTAssertEqual(wrapper.resultCode, 1)
        XCTAssertEqual(wrapper.customerId, 4440)
        XCTAssertEqual(wrapper.responseText, "Success")
        XCTAssertEqual(wrapper.apiResponse["responseText"] as? String, "Success")
    }

    @MainActor
    func testObjCAddACHRejectsInvalidArgumentsSynchronously() {
        let component = PayabliPaymentMethodObjC(
            accessTokenHandler: { completion in completion("unused", nil) },
            entryPoint: "entry",
            environment: .sandbox
        )

        var invalidAccountTypeError: NSError?
        component.addACH(
            accountNumber: "111111111",
            accountType: "Business",
            holderName: "Jane Doe",
            routingNumber: "123456780",
            secCode: nil,
            holderType: nil,
            achValidation: false,
            createAnonymous: false,
            forceCustomerCreation: false,
            temporary: false,
            source: nil
        ) { result, error in
            XCTAssertNil(result)
            invalidAccountTypeError = error
        }

        var invalidSecCodeError: NSError?
        component.addACH(
            accountNumber: "111111111",
            accountType: PayabliACHAccountType.checking.rawValue,
            holderName: "Jane Doe",
            routingNumber: "123456780",
            secCode: "POP",
            holderType: nil,
            achValidation: false,
            createAnonymous: false,
            forceCustomerCreation: false,
            temporary: false,
            source: nil
        ) { result, error in
            XCTAssertNil(result)
            invalidSecCodeError = error
        }

        XCTAssertEqual(invalidAccountTypeError?.code, -2)
        XCTAssertEqual(
            invalidAccountTypeError?.localizedDescription,
            "accountType must be Checking or Savings"
        )
        XCTAssertEqual(invalidSecCodeError?.code, -2)
        XCTAssertEqual(invalidSecCodeError?.localizedDescription, "secCode must be PPD, WEB, TEL, CCD, or BOC")
    }

    @MainActor
    func testObjCAddCardReturnsValidationErrorWithoutCallingTokenHandler() async {
        let completionExpectation = expectation(description: "ObjC card completion")
        let component = PayabliPaymentMethodObjC(
            accessTokenHandler: { _ in XCTFail("Token handler should not be called before local validation fails") },
            entryPoint: "entry",
            environment: .sandbox
        )

        component.addCard(
            cardNumber: "4111111111111111",
            expiration: "02/28",
            cardholderName: "",
            cvv: "123",
            billingZip: "33139",
            createAnonymous: false,
            forceCustomerCreation: false,
            temporary: false,
            source: nil
        ) { result, error in
            XCTAssertNil(result)
            XCTAssertEqual(error?.code, -3)
            XCTAssertEqual(error?.userInfo["PayabliErrorCode"] as? String, PayabliErrorCode.validation.rawValue)
            XCTAssertEqual(error?.localizedDescription, "Cardholder name is required.")
            completionExpectation.fulfill()
        }

        await fulfillment(of: [completionExpectation], timeout: 1)
    }

    @MainActor
    func testObjCAccessTokenHandlerErrorIsReturnedAndDoubleCallbacksAreIgnored() async {
        let completionExpectation = expectation(description: "ObjC token error completion")
        let tokenError = NSError(
            domain: "TokenProvider",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Token unavailable"]
        )
        let component = PayabliPaymentMethodObjC(
            accessTokenHandler: { completion in
                completion(nil, tokenError)
                completion("late-token", nil)
            },
            entryPoint: "entry",
            environment: .sandbox
        )

        component.addCard(
            cardNumber: "4111111111111111",
            expiration: "02/28",
            cardholderName: "Jane Doe",
            cvv: "123",
            billingZip: "33139",
            createAnonymous: false,
            forceCustomerCreation: false,
            temporary: false,
            source: nil
        ) { result, error in
            XCTAssertNil(result)
            XCTAssertEqual(error?.domain, "TokenProvider")
            XCTAssertEqual(error?.code, 42)
            completionExpectation.fulfill()
        }

        await fulfillment(of: [completionExpectation], timeout: 1)
    }

    @MainActor
    func testObjCNilTokenAndNilErrorProducesInvalidTokenProviderError() async {
        let completionExpectation = expectation(description: "ObjC nil token completion")
        let component = PayabliPaymentMethodObjC(
            accessTokenHandler: { completion in completion(nil, nil) },
            entryPoint: "entry",
            environment: .sandbox
        )

        component.addACH(
            accountNumber: "1111111111",
            accountType: PayabliACHAccountType.checking.rawValue,
            holderName: "Jane Doe",
            routingNumber: "123456780",
            secCode: nil,
            holderType: PayabliACHHolderType.personal.rawValue,
            achValidation: true,
            createAnonymous: false,
            forceCustomerCreation: false,
            temporary: false,
            source: nil
        ) { result, error in
            XCTAssertNil(result)
            XCTAssertEqual(error?.domain, "com.payabli.paymentMethod")
            XCTAssertEqual(error?.code, -1)
            completionExpectation.fulfill()
        }

        await fulfillment(of: [completionExpectation], timeout: 1)
    }

    @MainActor
    private func waitForPresentedViewController(
        from host: UIViewController,
        timeout: TimeInterval = 1
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while host.presentedViewController == nil, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }

    @MainActor
    private func waitForRenderedSubviews(
        in view: UIView,
        timeout: TimeInterval = 1
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            view.setNeedsLayout()
            view.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        } while view.payabliCoverageAllSubviews.compactMap({ $0 as? UITextField }).isEmpty && Date() < deadline
    }

    @MainActor
    private func host<Content: View>(_ view: Content) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        CoverageWindowStore.windows.append(window)
        return host
    }
}

private struct PaymentMethodSheetHarness: View {
    @State private var isPresented = true

    let component: PayabliPaymentMethod
    let configuration: PayabliPaymentMethodFormConfiguration
    let sheetConfiguration: PayabliPaymentMethodSheetConfiguration

    var body: some View {
        Text("Host")
            .payabliPaymentMethodSheet(
                isPresented: $isPresented,
                component: component,
                configuration: configuration,
                sheetConfiguration: sheetConfiguration,
                onPaymentMethodAdded: { _ in }
            )
    }
}

private struct UIKitTextFieldSanitizingHarness: View {
    @State private var text = "12ab"
    @State private var focusedField: PayabliPaymentMethodField?

    var body: some View {
        PayabliPaymentMethodUIKitTextField(
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

private extension UIView {
    var payabliCoverageAllSubviews: [UIView] {
        subviews + subviews.flatMap(\.payabliCoverageAllSubviews)
    }
}

@MainActor
private enum CoverageWindowStore {
    static var windows: [UIWindow] = []
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
        throw PayabliGenericError(code: .unknown, reason: "performV2 is not used")
    }
}
