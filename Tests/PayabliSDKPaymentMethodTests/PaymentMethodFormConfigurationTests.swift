@testable import PayabliSDKCore
@testable import PayabliSDKPaymentMethod
import SwiftUI
import UIKit
import XCTest

final class PaymentMethodFormConfigurationTests: XCTestCase {
    func testDetectsCardBrandFromCardNumberPrefix() {
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: "4111 1111 1111 1111"), .visa)
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: "5555 5555 5555 4444"), .mastercard)
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: "378282246310005"), .americanExpress)
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: "6011111111111117"), .discover)
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: "30569309025904"), .dinersClub)
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: "3530111333300000"), .jcb)
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: "6200000000000005"), .unionPay)
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: ""), .unknown)
    }

    func testCardBrandAssetNamesUsePayabliCatalogNames() {
        XCTAssertEqual(PayabliPaymentMethodCardBrand.visa.brandAssetName, "brand-visa")
        XCTAssertEqual(PayabliPaymentMethodCardBrand.mastercard.brandAssetName, "brand-mastercard")
        XCTAssertEqual(PayabliPaymentMethodCardBrand.americanExpress.brandAssetName, "brand-amex")
        XCTAssertEqual(PayabliPaymentMethodCardBrand.discover.brandAssetName, "brand-discover")
        XCTAssertNil(PayabliPaymentMethodCardBrand.unknown.brandAssetName)
        XCTAssertNil(PayabliPaymentMethodCardBrand.jcb.brandAssetName)
    }

    func testCardBrandIconPlacementIsConfigurable() {
        let configuration = PayabliPaymentMethodFormConfiguration(cardBrandIconPlacement: .leading)

        XCTAssertEqual(configuration.cardBrandIconPlacement, .leading)
    }

    func testErrorMessagePlacementIsConfigurable() {
        XCTAssertEqual(PayabliPaymentMethodFormConfiguration().errorMessagePlacement, .aboveSubmitButton)

        let configuration = PayabliPaymentMethodFormConfiguration(errorMessagePlacement: .top)

        XCTAssertEqual(configuration.errorMessagePlacement, .top)
    }

    func testPaymentMethodLabelsDefaultSubmitButtonText() {
        XCTAssertEqual(PayabliPaymentMethodLabels().submitButton, "Add Payment Method")
    }

    func testPaymentMethodLabelsUsePostalCodeCopy() {
        let labels = PayabliPaymentMethodLabels()

        XCTAssertEqual(labels.label(for: .cardZip), "Postal Code")
        XCTAssertEqual(labels.label(for: .billingZip), "Billing Postal Code")
    }

    func testPaymentMethodLabelsCanConfigureFieldPlaceholders() {
        let labels = PayabliPaymentMethodLabels(
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
        let defaultConfiguration = PayabliPaymentMethodFormConfiguration()
        XCTAssertTrue(defaultConfiguration.showsFieldLabels)
        XCTAssertTrue(defaultConfiguration.hiddenFieldLabels.isEmpty)

        let placeholderLayoutConfiguration = PayabliPaymentMethodFormConfiguration(labelLayout: .placeholder)
        XCTAssertFalse(placeholderLayoutConfiguration.showsFieldLabels)

        let configuration = PayabliPaymentMethodFormConfiguration(
            labels: PayabliPaymentMethodLabels(
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
        let configuration = PayabliPaymentMethodFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPaymentMethodFieldSection(
                    title: "Card Information",
                    fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip]
                ),
                PayabliPaymentMethodFieldSection(
                    title: "Customer Information",
                    fields: [.firstName, .lastName, .billingEmail]
                )
            ]
        )

        XCTAssertEqual(configuration.cardSections.map(\.title), [
            "Card Information",
            "Customer Information"
        ])
        XCTAssertEqual(configuration.cardFieldOrder, [
            .cardholderName,
            .cardNumber,
            .cardExpiration,
            .cardCvv,
            .cardZip,
            .firstName,
            .lastName,
            .billingEmail
        ])
    }

    func testFormConfigurationAppendsRequiredFieldsToSections() {
        let configuration = PayabliPaymentMethodFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPaymentMethodFieldSection(
                    title: "Card Information",
                    fields: [.cardNumber]
                ),
                PayabliPaymentMethodFieldSection(
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
        let configuration = PayabliPaymentMethodFormConfiguration(
            allowedMethods: [.ach],
            defaultMethod: .ach,
            achSections: [
                PayabliPaymentMethodFieldSection(
                    title: "Hidden",
                    fields: [.achSecCode]
                )
            ]
        )

        XCTAssertEqual(configuration.achSections.count, 1)
        XCTAssertEqual(configuration.achSections[0].fields, [
            .achHolder,
            .achRouting,
            .achAccount,
            .achAccountType
        ])
    }

    func testFormConfigurationRoutesRequiredACHAndCustomerFieldsToExistingSections() {
        let configuration = PayabliPaymentMethodFormConfiguration(
            allowedMethods: [.ach],
            defaultMethod: .ach,
            achSections: [
                PayabliPaymentMethodFieldSection(
                    title: "Customer",
                    fields: [.firstName]
                ),
                PayabliPaymentMethodFieldSection(
                    title: "Bank",
                    fields: [.achHolder]
                )
            ],
            requiredFields: [.billingZip, .achDevice]
        )

        XCTAssertEqual(configuration.achSections[0].fields, [
            .firstName,
            .achDevice,
            .billingZip
        ])
        XCTAssertEqual(configuration.achSections[1].fields, [
            .achHolder,
            .achRouting,
            .achAccount,
            .achAccountType
        ])
    }

    func testFieldSectionsCanOverrideSectionAndFieldSpacing() {
        let configuration = PayabliPaymentMethodFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPaymentMethodFieldSection(
                    title: "Card Information",
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
        var layout = PayabliPaymentMethodLayoutStyle()
        layout.inputVerticalSpacing = 18
        layout.inputHorizontalSpacing = 9

        XCTAssertEqual(layout.fieldGroupSpacing, 18)
        XCTAssertEqual(layout.pairedFieldSpacing, 9)
        XCTAssertEqual(layout.inputVerticalSpacing, 18)
        XCTAssertEqual(layout.inputHorizontalSpacing, 9)
    }

    func testInputStyleCanConfigureNativeTextFieldFontAndPlaceholderColor() {
        let uiFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
        let style = PayabliPaymentMethodInputStyle(
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
        let style = PayabliPaymentMethodStyle(
            accentColor: .purple,
            layout: PayabliPaymentMethodLayoutStyle(contentSpacing: 33)
        )
        var capturedSpacing: CGFloat?
        let host = UIHostingController(rootView: PaymentMethodStyleProbe { style in
            capturedSpacing = style.layout.contentSpacing
            expectation.fulfill()
        }
        .payabliPaymentMethodStyle(style))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()

        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(capturedSpacing, 33)
    }

    func testSheetConfigurationDefaultsToSdkOwnedPresentation() {
        let configuration = PayabliPaymentMethodSheetConfiguration()

        XCTAssertEqual(configuration.dismissButton, .close)
        XCTAssertTrue(configuration.dismissesOnSuccess)
        XCTAssertTrue(configuration.movesFormHeaderToSheetHeader)
        XCTAssertTrue(configuration.sizesToContentWhenPossible)
        XCTAssertTrue(configuration.expandsToLargeWhenContentDoesNotFit)
        XCTAssertFalse(configuration.detents.isEmpty)
    }

    func testSheetConfigurationUsesLargeDetentWhenGivenEmptySet() {
        let configuration = PayabliPaymentMethodSheetConfiguration(detents: Set<PresentationDetent>())

        XCTAssertEqual(configuration.detents, [.large])
    }

    @MainActor
    func testPaymentMethodLegacyConfigureWithThemeRoutesToCurrentConfigure() {
        let component = PayabliPaymentMethod(
            accessToken: "access-token",
            entryPoint: "old-entry",
            environment: .sandbox
        )
        let config = PayabliConfig(
            accessToken: "access-token",
            entryPoint: "new-entry",
            environment: .qa
        )

        component.configure(config: config, theme: .default)

        XCTAssertEqual(component.entryPoint, "new-entry")
        XCTAssertEqual(component.environment, .qa)
    }

    @MainActor
    func testViewModelInputLimitHelpers() {
        let viewModel = PayabliPaymentMethodViewModel(component: component())

        XCTAssertEqual(viewModel.limitCardholderName(String(repeating: "A", count: 61)).count, 60)
        XCTAssertEqual(viewModel.formatCardNumber(String(repeating: "4", count: 25)).digitsOnly.count, 19)
        XCTAssertEqual(viewModel.limitCardCvv("12345"), "1234")
        XCTAssertEqual(viewModel.limitPostalCode("A1A 1A1-EXTRA").count, 12)
        XCTAssertEqual(viewModel.limitACHHolderName(String(repeating: "A", count: 61)).count, 60)
        XCTAssertEqual(viewModel.limitACHRouting("1234567890"), "123456789")
        XCTAssertEqual(viewModel.limitACHAccount(String(repeating: "1", count: 20)).count, 17)

        viewModel.cardholderName = String(repeating: "A", count: 61)
        XCTAssertEqual(viewModel.cardholderName.count, 60)

        viewModel.cardNumber = String(repeating: "4", count: 25)
        XCTAssertEqual(viewModel.cardNumber.digitsOnly.count, 19)

        viewModel.cardCvv = "12345"
        XCTAssertEqual(viewModel.cardCvv, "1234")

        viewModel.cardZip = "A1A 1A1-EXTRA"
        XCTAssertEqual(viewModel.cardZip.count, 12)

        viewModel.achHolder = String(repeating: "A", count: 61)
        XCTAssertEqual(viewModel.achHolder.count, 60)

        viewModel.achRouting = "1234567890"
        XCTAssertEqual(viewModel.achRouting, "123456789")

        viewModel.achAccount = String(repeating: "1", count: 20)
        XCTAssertEqual(viewModel.achAccount.count, 17)

        viewModel.billingZip = "1234567890123"
        XCTAssertEqual(viewModel.billingZip.count, 12)
    }

    @MainActor
    func testViewModelFormatsTypedExpirationAndDefaultsPickerSelection() throws {
        let viewModel = PayabliPaymentMethodViewModel(
            component: component(),
            configuration: PayabliPaymentMethodFormConfiguration(
                allowedMethods: [.card],
                formatting: PayabliPaymentMethodFormatting(expirationSeparator: "-")
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
        XCTAssertEqual(viewModel.cardExpiration, "04/31")

        viewModel.cardExpirationMonth = nil
        viewModel.cardExpirationYear = nil
        viewModel.cardExpiration = ""
        viewModel.ensureExpirationSelection(defaultDate: defaultDate)

        XCTAssertEqual(viewModel.cardExpirationMonth, 3)
        XCTAssertEqual(viewModel.cardExpirationYear, 2030)
        XCTAssertEqual(viewModel.cardExpiration, "03/30")

        viewModel.selectExpirationMonth(99)
        XCTAssertEqual(viewModel.cardExpirationMonth, 12)
    }

    @MainActor
    func testViewModelReportsInvalidCardNumberAsUserTypes() {
        let viewModel = PayabliPaymentMethodViewModel(
            component: component(),
            configuration: PayabliPaymentMethodFormConfiguration(allowedMethods: [.card])
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
        let viewModel = PayabliPaymentMethodViewModel(
            component: PayabliPaymentMethod(
                accessToken: "access-token",
                entryPoint: "entry",
                environment: .sandbox,
                transport: ThrowingPaymentMethodTransport(error: PaymentMethodTestError.transportBoom)
            ),
            configuration: PayabliPaymentMethodFormConfiguration(allowedMethods: [.card])
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
        let viewModel = PayabliPaymentMethodViewModel(
            component: component(),
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
            )
        )
        viewModel.achHolder = "Jane Business"
        viewModel.achRouting = "123456780"
        viewModel.achAccount = "1111111111"
        viewModel.achDevice = "terminal-1"
        viewModel.methodDescription = "Business account"
        viewModel.firstName = "Jane"

        XCTAssertFalse(viewModel.canSubmit)

        do {
            _ = try await viewModel.submit()
            XCTFail("Expected required field validation error")
        } catch let PayabliPaymentMethodError.invalidInput(message) {
            XCTAssertEqual(message, "Last name is required.")
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        viewModel.lastName = "Doe"
        viewModel.customerNumber = "cust-1"
        viewModel.billingEmail = "jane@example.com"
        viewModel.billingZip = "33139"

        XCTAssertTrue(viewModel.canSubmit)
    }

    @MainActor
    func testViewModelEvaluatesRequiredPickerAndExpirationFields() {
        let cardViewModel = PayabliPaymentMethodViewModel(
            component: component(),
            configuration: PayabliPaymentMethodFormConfiguration(
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

        let achViewModel = PayabliPaymentMethodViewModel(
            component: component(),
            configuration: PayabliPaymentMethodFormConfiguration(
                allowedMethods: [.ach],
                defaultMethod: .ach,
                requiredFields: [.achHolderType]
            )
        )
        achViewModel.achHolder = "Jane Business"
        achViewModel.achRouting = "123456780"
        achViewModel.achAccount = "1111111111"

        XCTAssertTrue(achViewModel.canSubmit)
    }

    @MainActor
    func testViewModelBuildsExpirationFromMonthYearSelection() {
        let viewModel = PayabliPaymentMethodViewModel(
            component: component(),
            configuration: PayabliPaymentMethodFormConfiguration(allowedMethods: [.card])
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
    private func component() -> PayabliPaymentMethod {
        PayabliPaymentMethod(
            accessToken: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
    }
}

private struct PaymentMethodStyleProbe: View {
    @Environment(\.payabliPaymentMethodStyle) private var style

    let onAppear: (PayabliPaymentMethodStyle) -> Void

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
