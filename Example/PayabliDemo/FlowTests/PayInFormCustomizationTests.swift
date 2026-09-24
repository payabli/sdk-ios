import PayabliSDKPayInPaymentFlow
import XCTest

final class PayInFormCustomizationTests: XCTestCase {
    func testTheDefaultPresetIsTheSettingsTheScreenStartsOn() {
        let sdkDefault = PayabliPayInPaymentFlowFormConfiguration()
        let preset = PayInFormCustomization(preset: .sdkDefault)

        XCTAssertEqual(preset, PayInFormCustomization())
        XCTAssertEqual(preset.activePreset, .sdkDefault)
        XCTAssertEqual(preset.look, .appTheme)
        XCTAssertEqual(preset.methods, .cardAndBank)
        XCTAssertEqual(preset.startOn, .card)
        XCTAssertTrue(preset.showsCustomerSection)
        XCTAssertTrue(preset.showsAmountSummary)
        XCTAssertTrue(preset.groupsCardNumber)
        XCTAssertTrue(preset.masksAccountNumber)
        XCTAssertFalse(preset.labelsInsideFields)
        XCTAssertFalse(preset.hidesLabels)
        XCTAssertFalse(preset.usesCustomWording)
        XCTAssertFalse(preset.customerSectionFirst)
        XCTAssertFalse(preset.requiresCustomerNumber)
        XCTAssertFalse(preset.dashesExpiry)
        XCTAssertEqual(preset.cardBrandIconPlacement, sdkDefault.cardBrandIconPlacement)
        XCTAssertEqual(preset.errorMessagePlacement, sdkDefault.errorMessagePlacement)
        XCTAssertEqual(preset.inputSizing, .standard)
    }

    func testTheDefaultPresetHandsTheFormItsOwnWording() {
        let configuration = PayInFormCustomization(preset: .sdkDefault).configuration(capturing: true)
        let sdkDefault = PayabliPayInPaymentFlowFormConfiguration()

        XCTAssertEqual(configuration.allowedMethods, [.card, .bankAccount])
        XCTAssertEqual(configuration.labelLayout, .external)
        XCTAssertTrue(configuration.showsFieldLabels)
        XCTAssertEqual(configuration.labels.title, sdkDefault.labels.title)
        XCTAssertEqual(configuration.labels.submitButton, sdkDefault.labels.submitButton)
        XCTAssertEqual(configuration.inputSizing, sdkDefault.inputSizing)
        XCTAssertEqual(configuration.cardSections.map(\.title), [nil, nil, "Payment Information"])
    }

    func testTheBrandPreset() {
        let customization = PayInFormCustomization(preset: .brand)
        let configuration = customization.configuration(capturing: true)

        XCTAssertEqual(customization.activePreset, .brand)
        XCTAssertEqual(customization.look, .brand)
        XCTAssertEqual(customization.configuration(capturing: false).labels.submitButton, "Save for later")
        XCTAssertEqual(configuration.labelLayout, .placeholder)
        XCTAssertEqual(configuration.labels.title, "Acme Checkout")
        XCTAssertEqual(configuration.labels.subtitle, "Secure payment, powered by Payabli")
        XCTAssertEqual(configuration.labels.label(for: .customerNumber), "Member ID")
        XCTAssertEqual(configuration.cardSections.map(\.title), ["About you", "Your card", "Order total"])
        XCTAssertEqual(configuration.labels.submitButton, "Pay now")
        XCTAssertEqual(configuration.cardSections.first?.fields, [.firstName, .lastName, .customerNumber, .billingEmail])
        XCTAssertTrue(configuration.requiredFields.contains(.customerNumber))
        XCTAssertEqual(configuration.formatting.expirationSeparator, "-")
        XCTAssertEqual(configuration.cardBrandIconPlacement, .trailing)
        XCTAssertEqual(configuration.errorMessagePlacement, .top)
        XCTAssertEqual(configuration.inputSizing.size(for: .cardNumber).height, 60)
    }

    func testTheMinimalPreset() {
        let customization = PayInFormCustomization(preset: .minimal)
        let configuration = customization.configuration(capturing: true)

        XCTAssertEqual(customization.activePreset, .minimal)
        XCTAssertEqual(customization.look, .compact)
        XCTAssertEqual(configuration.allowedMethods, [.card])
        XCTAssertFalse(configuration.showsFieldLabels)
        XCTAssertEqual(configuration.labels.placeholder(for: .cardNumber), "Card number")
        XCTAssertFalse(configuration.cardSections.flatMap(\.fields).contains(.firstName))
        XCTAssertNil(configuration.cardSections.last?.title)
        XCTAssertFalse(configuration.formatting.insertsCardNumberSpaces)
        XCTAssertEqual(configuration.cardBrandIconPlacement, .hidden)
        XCTAssertEqual(configuration.errorMessagePlacement, .aboveSubmitButton)
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

        XCTAssertEqual(customization.configuration(capturing: true).defaultMethod, .bankAccount)

        customization.methods = .cardOnly

        XCTAssertEqual(customization.configuration(capturing: true).defaultMethod, .card)
    }

    func testEachSettingReachesTheFormOnItsOwn() {
        var customization = PayInFormCustomization()
        customization.methods = .bankOnly
        customization.labelsInsideFields = true
        customization.dashesExpiry = true
        customization.groupsCardNumber = false
        customization.masksAccountNumber = false
        customization.cardBrandIconPlacement = .hidden
        customization.errorMessagePlacement = .aboveSubmitButton
        customization.inputSizing = .large

        let configuration = customization.configuration(capturing: false)

        XCTAssertEqual(configuration.allowedMethods, [.bankAccount])
        XCTAssertEqual(configuration.labelLayout, .placeholder)
        XCTAssertEqual(configuration.formatting.expirationSeparator, "-")
        XCTAssertFalse(configuration.formatting.insertsCardNumberSpaces)
        XCTAssertFalse(configuration.formatting.masksACHAccountEntry)
        XCTAssertEqual(configuration.cardBrandIconPlacement, .hidden)
        XCTAssertEqual(configuration.errorMessagePlacement, .aboveSubmitButton)
        XCTAssertEqual(configuration.inputSizing.size(for: .achRouting).height, 60)
    }

    func testTheCustomerSectionFollowsThePaymentUnlessMovedFirst() {
        var customization = PayInFormCustomization()

        XCTAssertEqual(
            customization.configuration(capturing: true).cardSections.map(\.fields.first),
            [.cardholderName, .firstName, .amount]
        )

        customization.customerSectionFirst = true

        XCTAssertEqual(
            customization.configuration(capturing: true).cardSections.map(\.fields.first),
            [.firstName, .cardholderName, .amount]
        )
    }
}
