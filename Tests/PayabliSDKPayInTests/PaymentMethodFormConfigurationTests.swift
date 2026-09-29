@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import SwiftUI
import UIKit
import XCTest

final class PaymentMethodFormConfigurationTests: XCTestCase {
    func testDetectsCardBrandFromCardNumberPrefix() {
        XCTAssertEqual(PayabliPayInCardBrand.detect(cardNumber: "4111 1111 1111 1111"), .visa)
        XCTAssertEqual(PayabliPayInCardBrand.detect(cardNumber: "5555 5555 5555 4444"), .mastercard)
        XCTAssertEqual(PayabliPayInCardBrand.detect(cardNumber: "378282246310005"), .americanExpress)
        XCTAssertEqual(PayabliPayInCardBrand.detect(cardNumber: "6011111111111117"), .discover)
        XCTAssertEqual(PayabliPayInCardBrand.detect(cardNumber: "30569309025904"), .dinersClub)
        XCTAssertEqual(PayabliPayInCardBrand.detect(cardNumber: "3530111333300000"), .jcb)
        XCTAssertEqual(PayabliPayInCardBrand.detect(cardNumber: "6200000000000005"), .unionPay)
        XCTAssertEqual(PayabliPayInCardBrand.detect(cardNumber: ""), .unknown)
    }

    func testCardBrandAssetNamesUsePayabliCatalogNames() {
        XCTAssertEqual(PayabliPayInCardBrand.visa.brandAssetName, "brand-visa")
        XCTAssertEqual(PayabliPayInCardBrand.mastercard.brandAssetName, "brand-mastercard")
        XCTAssertEqual(PayabliPayInCardBrand.americanExpress.brandAssetName, "brand-amex")
        XCTAssertEqual(PayabliPayInCardBrand.discover.brandAssetName, "brand-discover")
        XCTAssertNil(PayabliPayInCardBrand.unknown.brandAssetName)
        XCTAssertNil(PayabliPayInCardBrand.jcb.brandAssetName)
    }

    func testCardBrandIconPlacementIsConfigurable() {
        let configuration = PayabliPayInFormConfiguration(cardBrandIconPlacement: .leading)

        XCTAssertEqual(configuration.cardBrandIconPlacement, .leading)
    }

    func testErrorMessagePlacementIsConfigurable() {
        XCTAssertEqual(PayabliPayInFormConfiguration().errorMessagePlacement, .aboveSubmitButton)

        let configuration = PayabliPayInFormConfiguration(errorMessagePlacement: .top)

        XCTAssertEqual(configuration.errorMessagePlacement, .top)
    }

    func testPaymentMethodLabelsDefaultSubmitButtonText() {
        XCTAssertEqual(PayabliPayInLabels().submitButton, "Add Payment Method")
    }

    func testPaymentMethodLabelsUsePostalCodeCopy() {
        let labels = PayabliPayInLabels()

        XCTAssertEqual(labels.label(for: .cardZip), "Postal Code")
        XCTAssertEqual(labels.label(for: .billingZip), "Billing Postal Code")
    }

    func testPaymentMethodLabelsCanConfigureFieldPlaceholders() {
        let labels = PayabliPayInLabels(
            fieldLabels: [.cardNumber: "Card #"],
            fieldPlaceholders: [
                .cardNumber: "1234 1234 1234 1234",
                .billingEmail: "customer@example.com"
            ]
        )

        XCTAssertEqual(labels.label(for: .cardNumber), "Card #")
        XCTAssertEqual(labels.placeholder(for: .cardNumber), "1234 1234 1234 1234")
        XCTAssertEqual(labels.placeholder(for: .billingEmail), "customer@example.com")
        XCTAssertNil(labels.placeholder(for: .cardCvv))
    }

    func testFormConfigurationCanHideExternalLabelsIndependentlyOfPlaceholders() {
        let defaultConfiguration = PayabliPayInFormConfiguration()
        XCTAssertTrue(defaultConfiguration.showsFieldLabels)
        XCTAssertTrue(defaultConfiguration.hiddenFieldLabels.isEmpty)

        let placeholderLayoutConfiguration = PayabliPayInFormConfiguration(labelLayout: .placeholder)
        XCTAssertFalse(placeholderLayoutConfiguration.showsFieldLabels)

        let configuration = PayabliPayInFormConfiguration(
            labels: PayabliPayInLabels(
                fieldPlaceholders: [.cardNumber: "Enter card number"]
            ),
            labelLayout: .external,
            showsFieldLabels: false,
            hiddenFieldLabels: [.cardCvv]
        )

        XCTAssertFalse(configuration.showsFieldLabels)
        XCTAssertEqual(configuration.labels.placeholder(for: .cardNumber), "Enter card number")
        XCTAssertTrue(configuration.hiddenFieldLabels.contains(.cardCvv))
    }

    func testFormConfigurationCanGroupFieldsIntoSections() {
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPayInFieldSection(
                    title: "Card Information",
                    fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip]
                ),
                PayabliPayInFieldSection(
                    title: "Customer Information",
                    fields: [.firstName, .lastName, .billingEmail]
                )
            ]
        )

        XCTAssertEqual(configuration.cardSections.map(\.title), [
            "Card Information",
            "Customer Information",
            "Payment Information"
        ])
        XCTAssertEqual(configuration.cardFieldOrder, [
            .cardholderName,
            .cardNumber,
            .cardExpiration,
            .cardCvv,
            .cardZip,
            .firstName,
            .lastName,
            .billingEmail,
            .amount,
            .serviceFee
        ])
    }

    func testFormConfigurationAppendsRequiredFieldsToSections() {
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPayInFieldSection(
                    title: "Card Information",
                    fields: [.cardNumber]
                ),
                PayabliPayInFieldSection(
                    title: "Customer Information",
                    fields: [.firstName]
                )
            ],
            requiredFields: [.billingEmail]
        )

        XCTAssertEqual(configuration.cardSections[0].fields, [
            .cardNumber,
            .cardExpiration,
            .cardholderName,
            .cardCvv,
            .cardZip
        ])
        XCTAssertEqual(configuration.cardSections[1].fields, [
            .firstName,
            .billingEmail
        ])
    }

    func testFormConfigurationAppendsACHRequiredFieldsWhenProvidedSectionsAreHidden() {
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.bankAccount],
            defaultMethod: .bankAccount,
            bankSections: [
                PayabliPayInFieldSection(
                    title: "Hidden",
                    fields: [.secCode]
                )
            ]
        )

        XCTAssertEqual(configuration.bankSections.count, 2)
        XCTAssertEqual(configuration.bankSections[0].fields, [
            .accountHolder,
            .routingNumber,
            .accountNumber,
            .accountType
        ])
        XCTAssertEqual(configuration.bankSections[1].title, "Payment Information")
        XCTAssertEqual(configuration.bankSections[1].fields, [.amount, .serviceFee])
    }

    func testFormConfigurationRoutesRequiredACHAndCustomerFieldsToExistingSections() {
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.bankAccount],
            defaultMethod: .bankAccount,
            bankSections: [
                PayabliPayInFieldSection(
                    title: "Customer",
                    fields: [.firstName]
                ),
                PayabliPayInFieldSection(
                    title: "Bank",
                    fields: [.accountHolder]
                )
            ],
            requiredFields: [.billingZip, .deviceId]
        )

        XCTAssertEqual(configuration.bankSections[0].fields, [
            .firstName,
            .deviceId,
            .billingZip
        ])
        XCTAssertEqual(configuration.bankSections[1].fields, [
            .accountHolder,
            .routingNumber,
            .accountNumber,
            .accountType
        ])
    }

    func testFieldSectionsCanOverrideSectionAndFieldSpacing() {
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPayInFieldSection(
                    title: "Card Information",
                    titleStyle: PayabliPayInTextStyle(
                        font: .headline,
                        color: .blue
                    ),
                    fields: [.cardNumber],
                    inputVerticalSpacing: 4,
                    inputHorizontalSpacing: 8,
                    fieldVerticalSpacings: [
                        .cardNumber: 2,
                        .cardCvv: -1
                    ]
                )
            ]
        )

        let section = configuration.cardSections[0]
        XCTAssertNotNil(section.titleStyle)
        XCTAssertEqual(section.inputVerticalSpacing, CGFloat(4))
        XCTAssertEqual(section.inputHorizontalSpacing, CGFloat(8))
        XCTAssertEqual(section.fieldVerticalSpacings[.cardNumber], CGFloat(2))
        XCTAssertEqual(section.fieldVerticalSpacings[.cardCvv], CGFloat(0))
        XCTAssertEqual(section.fields, [
            .cardNumber,
            .cardExpiration,
            .cardholderName,
            .cardCvv,
            .cardZip
        ])
    }

    func testLayoutStyleExposesInputSpacingAliases() {
        var layout = PayabliPayInLayoutStyle()
        layout.inputVerticalSpacing = 18
        layout.inputHorizontalSpacing = 9

        XCTAssertEqual(layout.fieldGroupSpacing, 18)
        XCTAssertEqual(layout.pairedFieldSpacing, 9)
        XCTAssertEqual(layout.inputVerticalSpacing, 18)
        XCTAssertEqual(layout.inputHorizontalSpacing, 9)

        layout.inputVerticalSpacing = -1
        layout.inputHorizontalSpacing = -2

        XCTAssertEqual(layout.fieldGroupSpacing, 0)
        XCTAssertEqual(layout.pairedFieldSpacing, 0)
    }

    func testInputStyleCanConfigureNativeTextFieldFontAndPlaceholderColor() {
        let uiFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
        let style = PayabliPayInInputStyle(
            font: .headline,
            uiFont: uiFont,
            textColor: .blue,
            placeholderColor: .red
        )

        XCTAssertEqual(style.uiFont?.pointSize, 15)
        XCTAssertEqual(style.uiFont?.fontName, uiFont.fontName)
        XCTAssertEqual(style.resolvedUIFont.pointSize, 15)
    }

    @MainActor
    func testStyleModifierWritesEnvironmentStyle() async {
        let expectation = expectation(description: "Style probe appeared")
        let style = PayabliPayInStyle(
            accentColor: .purple,
            layout: PayabliPayInLayoutStyle(contentSpacing: 33)
        )
        var capturedSpacing: CGFloat?
        let host = UIHostingController(rootView: PaymentMethodStyleProbe { style in
            capturedSpacing = style.layout.contentSpacing
            expectation.fulfill()
        }
        .payabliPayInStyle(style))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()

        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(capturedSpacing, 33)
    }

    func testSheetConfigurationDefaultsToSdkOwnedPresentation() {
        let configuration = PayabliPayInSheetConfiguration()

        XCTAssertEqual(configuration.dismissButton, .close)
        XCTAssertTrue(configuration.dismissesOnSuccess)
        XCTAssertTrue(configuration.movesFormHeaderToSheetHeader)
        XCTAssertTrue(configuration.sizesToContentWhenPossible)
        XCTAssertTrue(configuration.expandsToLargeWhenContentDoesNotFit)
        XCTAssertFalse(configuration.detents.isEmpty)
    }

    func testSheetConfigurationUsesLargeDetentWhenGivenEmptySet() {
        let configuration = PayabliPayInSheetConfiguration(detents: Set<PresentationDetent>())

        XCTAssertEqual(configuration.detents, [.large])
    }

    @MainActor
    func testPaymentMethodLegacyConfigureWithThemeRoutesToCurrentConfigure() throws {
        let component = flowOnSession(
            token: "access-token",
            entryPoint: "old-entry",
            environment: .sandbox
        )
        let config = try PayabliConfig(
            entryPoint: "new-entry",
            environment: .qa,

            tokenProvider: { "access-token" }
        )

        component.configure(config: config, theme: .default)

        XCTAssertEqual(component.entryPoint, "new-entry")
        XCTAssertEqual(component.environment, .qa)
    }

    @MainActor
    func testViewModelInputLimitHelpers() {
        let viewModel = PayabliPayInViewModel(component: component())

        XCTAssertEqual(viewModel.limitCardholderName(String(repeating: "A", count: 61)).count, 60)
        XCTAssertEqual(viewModel.formatCardNumber(String(repeating: "4", count: 25)).digitsOnly.count, 19)
        XCTAssertEqual(viewModel.limitCardCvv("12345"), "1234")
        XCTAssertEqual(viewModel.limitPostalCode("A1A 1A1-EXTRA").count, 12)
        XCTAssertEqual(viewModel.limitAccountHolderName(String(repeating: "A", count: 61)).count, 60)
        XCTAssertEqual(viewModel.limitRoutingNumber("1234567890"), "123456789")
        XCTAssertEqual(viewModel.limitAccountNumber(String(repeating: "1", count: 20)).count, 17)

        viewModel.cardholderName = String(repeating: "A", count: 61)
        XCTAssertEqual(viewModel.cardholderName.count, 60)

        viewModel.cardNumber = String(repeating: "4", count: 25)
        XCTAssertEqual(viewModel.cardNumber.digitsOnly.count, 19)

        viewModel.cardCvv = "12345"
        XCTAssertEqual(viewModel.cardCvv, "1234")

        viewModel.cardZip = "A1A 1A1-EXTRA"
        XCTAssertEqual(viewModel.cardZip.count, 12)

        viewModel.accountHolder = String(repeating: "A", count: 61)
        XCTAssertEqual(viewModel.accountHolder.count, 60)

        viewModel.routingNumber = "1234567890"
        XCTAssertEqual(viewModel.routingNumber, "123456789")

        viewModel.accountNumber = String(repeating: "1", count: 20)
        XCTAssertEqual(viewModel.accountNumber.count, 17)

        viewModel.billingZip = "1234567890123"
        XCTAssertEqual(viewModel.billingZip.count, 12)
    }

    @MainActor
    func testViewModelFormatsTypedExpirationAndDefaultsPickerSelection() throws {
        let viewModel = PayabliPayInViewModel(
            component: component(),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.card],
                formatting: PayabliPayInFormatting(expirationSeparator: "-")
            )
        )

        XCTAssertEqual(viewModel.formatExpiration("1"), "1")
        XCTAssertEqual(viewModel.formatExpiration("1229"), "12-29")

        viewModel.selectExpirationYear(2031)
        XCTAssertEqual(viewModel.expirationDisplayText, "MM/31")
        XCTAssertEqual(viewModel.cardExpiration, "")

        var components = DateComponents()
        components.year = 2030
        components.month = 3
        components.day = 10
        let defaultDate = try XCTUnwrap(Calendar.current.date(from: components))
        viewModel.cardExpirationMonth = nil
        viewModel.cardExpirationYear = nil
        viewModel.cardExpiration = "04/31"

        viewModel.ensureExpirationSelection(defaultDate: defaultDate)

        XCTAssertEqual(viewModel.cardExpirationMonth, 4)
        XCTAssertEqual(viewModel.cardExpirationYear, 2031)
        XCTAssertEqual(viewModel.cardExpiration, "04-31")

        viewModel.cardExpirationMonth = nil
        viewModel.cardExpirationYear = nil
        viewModel.cardExpiration = ""
        viewModel.ensureExpirationSelection(defaultDate: defaultDate)

        XCTAssertEqual(viewModel.cardExpirationMonth, 3)
        XCTAssertEqual(viewModel.cardExpirationYear, 2030)
        XCTAssertEqual(viewModel.cardExpiration, "03-30")

        viewModel.selectExpirationMonth(99)
        XCTAssertEqual(viewModel.cardExpirationMonth, 12)
    }

    @MainActor
    func testViewModelReportsInvalidCardNumberAsUserTypes() {
        let viewModel = PayabliPayInViewModel(
            component: component(),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card])
        )

        viewModel.cardNumber = "4111 1111"
        XCTAssertNil(viewModel.cardNumberValidationMessage)

        viewModel.cardNumber = "4111 1111 1111 1112"
        XCTAssertEqual(viewModel.cardNumberValidationMessage, "Invalid Card Number")

        viewModel.cardholderName = "Jane Doe"
        viewModel.cardExpiration = "02/28"
        viewModel.cardCvv = "123"
        viewModel.cardZip = "33139"
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.cardNumber = "4111 1111 1111 1111"
        XCTAssertNil(viewModel.cardNumberValidationMessage)
        XCTAssertTrue(viewModel.canSubmit)
    }

    @MainActor
    func testViewModelUsesStringDescriptionForNonPayabliErrors() async {
        let viewModel = PayabliPayInViewModel(
            component: PayabliPayIn(
                entryPoint: "entry",
                environment: .sandbox,
                transport: ThrowingPaymentMethodTransport(error: PaymentMethodTestError.transportBoom)
            ),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card])
        )
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "02/28"
        viewModel.cardCvv = "123"
        viewModel.cardZip = "33139"

        do {
            _ = try await viewModel.submit()
            XCTFail("Expected transport error")
        } catch PaymentMethodTestError.transportBoom {
            XCTAssertEqual(viewModel.errorMessage, "transportBoom")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    @MainActor
    func testViewModelRequiresACHCustomerFieldsBeforeSubmit() async {
        let viewModel = PayabliPayInViewModel(
            component: component(),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.bankAccount],
                defaultMethod: .bankAccount,
                requiredFields: [
                    .deviceId,
                    .methodDescription,
                    .firstName,
                    .lastName,
                    .customerNumber,
                    .billingEmail,
                    .billingZip
                ]
            )
        )
        viewModel.accountHolder = "Jane Business"
        viewModel.routingNumber = "123456780"
        viewModel.accountNumber = "1111111111"
        viewModel.deviceId = "terminal-1"
        viewModel.methodDescription = "Business account"
        viewModel.firstName = "Jane"

        XCTAssertFalse(viewModel.canSubmit)

        do {
            _ = try await viewModel.submit()
            XCTFail("Expected required field validation error")
        } catch let error as any PayabliError {
            XCTAssertEqual(error.reason, "Last name is required.")
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        XCTAssertEqual(viewModel.routingNumber, "")
        XCTAssertEqual(viewModel.accountNumber, "")

        viewModel.routingNumber = "123456780"
        viewModel.accountNumber = "1111111111"
        viewModel.lastName = "Doe"
        viewModel.customerNumber = "cust-1"
        viewModel.billingEmail = "jane@example.com"
        viewModel.billingZip = "33139"

        XCTAssertTrue(viewModel.canSubmit)
    }

    @MainActor
    func testViewModelEvaluatesRequiredPickerAndExpirationFields() {
        let cardViewModel = PayabliPayInViewModel(
            component: component(),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.card],
                requiredFields: [.cardExpiration]
            )
        )
        cardViewModel.cardholderName = "Jane Doe"
        cardViewModel.cardNumber = "4111111111111111"
        cardViewModel.cardCvv = "123"
        cardViewModel.cardZip = "33139"

        XCTAssertFalse(cardViewModel.canSubmit)

        cardViewModel.cardExpiration = "02/28"

        XCTAssertTrue(cardViewModel.canSubmit)

        let achViewModel = PayabliPayInViewModel(
            component: component(),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.bankAccount],
                defaultMethod: .bankAccount,
                requiredFields: [.accountHolderType]
            )
        )
        achViewModel.accountHolder = "Jane Business"
        achViewModel.routingNumber = "123456780"
        achViewModel.accountNumber = "1111111111"

        XCTAssertTrue(achViewModel.canSubmit)
    }

    @MainActor
    func testViewModelBuildsExpirationFromMonthYearSelection() {
        let viewModel = PayabliPayInViewModel(
            component: component(),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card])
        )

        XCTAssertEqual(viewModel.expirationDisplayText, "MM/YY")

        viewModel.selectExpirationMonth(2)
        XCTAssertEqual(viewModel.expirationDisplayText, "02/YY")
        XCTAssertEqual(viewModel.cardExpiration, "")

        viewModel.selectExpirationYear(2028)
        XCTAssertEqual(viewModel.expirationDisplayText, "02/28")
        XCTAssertEqual(viewModel.cardExpiration, "02/28")
    }

    @MainActor
    private func component() -> PayabliPayIn {
        flowOnSession(
            token: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
    }
}

private struct PaymentMethodStyleProbe: View {
    @Environment(\.payabliPayInStyle) private var style

    let onAppear: (PayabliPayInStyle) -> Void

    var body: some View {
        Text("Style probe")
            .onAppear {
                onAppear(style)
            }
    }
}

private enum PaymentMethodTestError: Error {
    case transportBoom
}

private actor ThrowingPaymentMethodTransport: PayabliTransport {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        throw error
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        throw PayabliGenericError(code: .unknown, reason: "performV2 is not used")
    }
}
