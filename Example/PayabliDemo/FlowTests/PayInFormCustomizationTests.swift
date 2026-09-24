import PayabliSDKPayInPaymentFlow
import XCTest

final class PayInFormCustomizationTests: XCTestCase {
    private let sdkDefault = PayabliPayInPaymentFlowFormConfiguration()

    func testTheDefaultPresetHandsTheFormWhatItWouldHaveUsedAnyway() {
        let configuration = PayInFormCustomization(preset: .sdkDefault).configuration(capturing: true)

        XCTAssertEqual(configuration.allowedMethods, sdkDefault.allowedMethods)
        XCTAssertEqual(configuration.labelLayout, sdkDefault.labelLayout)
        XCTAssertEqual(configuration.showsFieldLabels, sdkDefault.showsFieldLabels)
        XCTAssertEqual(configuration.cardBrandIconPlacement, sdkDefault.cardBrandIconPlacement)
        XCTAssertEqual(configuration.errorMessagePlacement, sdkDefault.errorMessagePlacement)
        XCTAssertEqual(configuration.inputSizing, sdkDefault.inputSizing)
        XCTAssertEqual(configuration.labels.title, sdkDefault.labels.title)
        XCTAssertEqual(configuration.labels.submitButton, sdkDefault.labels.submitButton)
        XCTAssertEqual(configuration.cardSections.map(\.title), sdkDefault.cardSections.map(\.title))
        XCTAssertEqual(configuration.cardSections.map(\.fields), sdkDefault.cardSections.map(\.fields))
    }

    func testTheBrandPresetPutsTheCustomerFirstAndRenamesTheForm() {
        let configuration = PayInFormCustomization(preset: .brand).configuration(capturing: true)

        XCTAssertEqual(configuration.cardSections.first?.fields, [.firstName, .lastName, .billingEmail])
        XCTAssertEqual(configuration.labelLayout, .placeholder)
        XCTAssertEqual(configuration.labels.title, "Checkout")
        XCTAssertEqual(configuration.labels.submitButton, "Pay now")
        XCTAssertEqual(configuration.labels.label(for: .billingEmail), "Email for receipt")
        XCTAssertEqual(configuration.cardBrandIconPlacement, .trailing)
        XCTAssertEqual(configuration.errorMessagePlacement, .top)
        XCTAssertEqual(configuration.inputSizing.size(for: .cardNumber).height, 60)
    }

    func testTheMinimalPresetStripsTheFormDown() {
        let configuration = PayInFormCustomization(preset: .minimal).configuration(capturing: true)

        XCTAssertEqual(configuration.allowedMethods, [.card])
        XCTAssertEqual(configuration.labelLayout, .placeholder)
        XCTAssertFalse(configuration.showsFieldLabels)
        XCTAssertEqual(configuration.cardSections.map(\.title), [nil, nil])
        XCTAssertEqual(configuration.cardBrandIconPlacement, .hidden)
        XCTAssertEqual(configuration.errorMessagePlacement, .aboveSubmitButton)
        XCTAssertEqual(configuration.inputSizing.size(for: .cardNumber).height, 44)
    }

    func testEveryPresetDiffersFromEveryOther() {
        let presets = PayInFormCustomization.Preset.allCases.map(PayInFormCustomization.init(preset:))

        XCTAssertEqual(Set(presets.map { "\($0)" }).count, presets.count)
    }

    func testEachSettingReachesTheFormOnItsOwn() {
        var customization = PayInFormCustomization(preset: .sdkDefault)
        customization.methods = .bankOnly
        customization.cardBrandIconPlacement = .leading
        customization.errorMessagePlacement = .top
        customization.usesDashExpirationSeparator = true
        customization.insertsCardNumberSpaces = false
        customization.masksACHAccountEntry = false
        customization.showsFieldLabels = false
        customization.inputSizing = .large

        let configuration = customization.configuration(capturing: false)

        XCTAssertEqual(configuration.allowedMethods, [.bankAccount])
        XCTAssertEqual(configuration.defaultMethod, .bankAccount)
        XCTAssertEqual(configuration.cardBrandIconPlacement, .leading)
        XCTAssertEqual(configuration.errorMessagePlacement, .top)
        XCTAssertEqual(configuration.formatting.expirationSeparator, "-")
        XCTAssertFalse(configuration.formatting.insertsCardNumberSpaces)
        XCTAssertFalse(configuration.formatting.masksACHAccountEntry)
        XCTAssertFalse(configuration.showsFieldLabels)
        XCTAssertEqual(configuration.inputSizing.size(for: .achRouting).height, 60)
    }

    func testTheCustomerSectionFollowsThePaymentUnlessMovedFirst() {
        var customization = PayInFormCustomization(preset: .sdkDefault)
        customization.showsCustomerSection = true

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

    func testTheSummaryHeadingCanBeDropped() {
        var customization = PayInFormCustomization(preset: .sdkDefault)
        customization.titlesPaymentSummary = false

        XCTAssertNil(customization.configuration(capturing: true).cardSections.last?.title)
    }
}
