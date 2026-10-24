import PayabliSDKPayIn
import XCTest

final class PayInFormCustomizationTests: XCTestCase {
    func testTheDefaultPresetIsTheSettingsTheScreenStartsOn() {
        let sdkDefault = PayabliPayInFormConfiguration()
        let preset = PayInFormCustomization(preset: .sdkDefault)

        XCTAssertEqual(preset, PayInFormCustomization())
        XCTAssertEqual(preset.activePreset, .sdkDefault)
        XCTAssertEqual(preset.look, .sdkDefault)
        XCTAssertFalse(preset.fixesHolderType)
        XCTAssertEqual(preset.methods, .cardAndBank)
        XCTAssertEqual(preset.startOn, .card)
        XCTAssertFalse(preset.showsCustomerSection)
        XCTAssertTrue(preset.groupsCardNumber)
        XCTAssertTrue(preset.masksAccountNumber)
        XCTAssertFalse(preset.labelsInsideFields)
        XCTAssertFalse(preset.hidesLabels)
        XCTAssertFalse(preset.usesCustomWording)
        XCTAssertFalse(preset.customerSectionFirst)
        XCTAssertFalse(preset.requiresCustomerNumber)
        XCTAssertFalse(preset.dashesExpiry)
        XCTAssertEqual(preset.cardBrandIconPlacement, sdkDefault.cardBrandIconPlacement)
        XCTAssertEqual(preset.failureMessagePlacement, sdkDefault.failureMessagePlacement)
        XCTAssertEqual(preset.inputSizing, .standard)
    }

    func testTheDefaultPresetHandsTheFormItsOwnWording() {
        let customization = PayInFormCustomization(preset: .sdkDefault)
        let configuration = customization.configuration(for: .capture)
        let labels = customization.labels(for: .capture)
        let sdkDefaultLabels = PayabliPayInFormLabels()

        XCTAssertEqual(configuration.allowedMethods, [.card, .bankAccount])
        XCTAssertEqual(configuration.labelLayout, .external)
        XCTAssertTrue(configuration.showsFieldLabels)
        XCTAssertEqual(labels.title, sdkDefaultLabels.title)
        XCTAssertEqual(labels.submitButton, sdkDefaultLabels.submitButton)
        XCTAssertEqual(configuration.inputSizing, PayabliPayInFormConfiguration().inputSizing)
        XCTAssertEqual(
            configuration.cardSections.map(\.title),
            PayabliPayInFormConfiguration().cardSections.map(\.title)
        )
        XCTAssertEqual(
            configuration.cardSections.map(\.fields),
            PayabliPayInFormConfiguration().cardSections.map(\.fields)
        )
        XCTAssertEqual(
            configuration.bankSections.map(\.fields),
            PayabliPayInFormConfiguration().bankSections.map(\.fields)
        )
        XCTAssertNil(configuration.hiddenValues.accountHolderType)
        let style = customization.style
        XCTAssertEqual(style.accentColor, PayabliPayInFormStyle.default.accentColor)
        XCTAssertEqual(style.input.backgroundColor, PayabliPayInFormStyle.default.input.backgroundColor)
    }

    func testTheBrandPreset() {
        let customization = PayInFormCustomization(preset: .brand)
        let configuration = customization.configuration(for: .capture)
        let labels = customization.labels(for: .capture)

        XCTAssertEqual(customization.activePreset, .brand)
        XCTAssertEqual(customization.look, .brand)
        XCTAssertEqual(customization.labels(for: .storedMethod).submitButton, "Save for later")
        XCTAssertEqual(configuration.labelLayout, .placeholder)
        XCTAssertEqual(labels.title, "Acme Checkout")
        XCTAssertEqual(labels.subtitle, "Secure payment, powered by Payabli")
        XCTAssertEqual(labels.label(for: .customerNumber), "Member ID")
        XCTAssertEqual(configuration.cardSections.map(\.title), ["About you", "Your card", "Order total"])
        XCTAssertEqual(labels.submitButton, "Pay now")
        XCTAssertEqual(configuration.cardSections.first?.fields, [.firstName, .lastName, .customerNumber, .billingEmail])
        XCTAssertTrue(configuration.requiredFields.contains(.customerNumber))
        XCTAssertEqual(configuration.formatting.expirationSeparator, "-")
        XCTAssertEqual(configuration.cardBrandIconPlacement, .trailing)
        XCTAssertEqual(configuration.failureMessagePlacement, .top)
        XCTAssertEqual(configuration.inputSizing.size(for: .cardNumber).height, 60)
    }

    func testTheMinimalPreset() {
        let customization = PayInFormCustomization(preset: .minimal)
        let configuration = customization.configuration(for: .capture)

        XCTAssertEqual(customization.activePreset, .minimal)
        XCTAssertEqual(customization.look, .compact)
        XCTAssertEqual(configuration.allowedMethods, [.card])
        XCTAssertFalse(configuration.showsFieldLabels)
        XCTAssertEqual(customization.labels(for: .capture).placeholder(for: .cardNumber), "Card number")
        XCTAssertFalse(configuration.cardSections.flatMap(\.fields).contains(.firstName))
        XCTAssertNil(configuration.cardSections.last?.title)
        XCTAssertFalse(configuration.formatting.insertsCardNumberSpaces)
        XCTAssertEqual(configuration.cardBrandIconPlacement, .hidden)
        XCTAssertEqual(configuration.failureMessagePlacement, .aboveSubmitButton)
        XCTAssertEqual(configuration.inputSizing.size(for: .cardNumber).height, 44)
    }

    func testAChangedSettingLeavesNoPresetActive() {
        var customization = PayInFormCustomization(preset: .brand)
        customization.look = .compact

        XCTAssertNil(customization.activePreset)
    }

    func testStartOnAppliesOnlyWhenBothMethodsAreOffered() {
        var customization = PayInFormCustomization()
        customization.startOn = .bankAccount

        XCTAssertEqual(customization.configuration(for: .capture).defaultMethod, .bankAccount)

        customization.methods = .cardOnly

        XCTAssertEqual(customization.configuration(for: .capture).defaultMethod, .card)
    }

    func testEachSettingReachesTheFormOnItsOwn() {
        var customization = PayInFormCustomization()
        customization.methods = .bankOnly
        customization.labelsInsideFields = true
        customization.dashesExpiry = true
        customization.groupsCardNumber = false
        customization.masksAccountNumber = false
        customization.cardBrandIconPlacement = .hidden
        customization.failureMessagePlacement = .aboveSubmitButton
        customization.inputSizing = .large

        let configuration = customization.configuration(for: .storedMethod)

        XCTAssertEqual(configuration.allowedMethods, [.bankAccount])
        XCTAssertEqual(configuration.labelLayout, .placeholder)
        XCTAssertEqual(configuration.formatting.expirationSeparator, "-")
        XCTAssertFalse(configuration.formatting.insertsCardNumberSpaces)
        XCTAssertFalse(configuration.formatting.masksAccountNumber)
        XCTAssertEqual(configuration.cardBrandIconPlacement, .hidden)
        XCTAssertEqual(configuration.failureMessagePlacement, .aboveSubmitButton)
        XCTAssertEqual(configuration.inputSizing.size(for: .routingNumber).height, 60)
    }

    func testTheCustomerSectionFollowsThePaymentUnlessMovedFirst() {
        var customization = PayInFormCustomization()
        customization.showsCustomerSection = true

        XCTAssertEqual(
            customization.configuration(for: .capture).cardSections.map(\.fields.first),
            [.cardholderName, .firstName, .amount]
        )

        customization.customerSectionFirst = true

        XCTAssertEqual(
            customization.configuration(for: .capture).cardSections.map(\.fields.first),
            [.firstName, .cardholderName, .amount]
        )
    }

    func testACaptureAndASaveNameTheSameSource() {
        let capture = PayInRequests.freshCapture(suppliesCustomer: false, source: PayInFormCustomization.source)
        let save = PayInFormCustomization().configuration(for: .storedMethod)

        XCTAssertEqual(capture.source, PayInFormCustomization.source)
        XCTAssertEqual(save.options.source, PayInFormCustomization.source)
    }

    func testAnAuthorizationOffersTheCardAlone() {
        var customization = PayInFormCustomization()
        customization.methods = .bankOnly
        customization.startOn = .bankAccount

        let configuration = customization.configuration(for: .authorize)

        XCTAssertEqual(configuration.allowedMethods, [.card])
        XCTAssertEqual(configuration.defaultMethod, .card)
        XCTAssertNil(configuration.hiddenValues.customerData)
    }

    func testAnAuthorizationsCustomWordingPlacesAHold() {
        let customization = PayInFormCustomization(preset: .brand)

        XCTAssertEqual(customization.labels(for: .authorize).submitButton, "Place hold")
        XCTAssertNil(PayInFormCustomization().labels(for: .authorize).submitButton)
    }
}
