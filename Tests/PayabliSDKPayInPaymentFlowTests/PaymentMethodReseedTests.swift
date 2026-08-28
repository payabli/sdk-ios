import Combine
@testable import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow
import XCTest

/// What an update from the caller does to what the payer has typed.
///
/// The sibling's form is handed its values and decides on every composition whether
/// the caller supplied a different seed, so a comparison that answers "unchanged"
/// too readily submits the card the caller replaced. These establish which of those
/// questions this platform has.
@MainActor
final class PaymentMethodReseedTests: XCTestCase {
    // MARK: - What an update reaches

    /// An update carrying a different configuration leaves every typed value alone.
    ///
    /// The caller can change the form under a payer mid-entry — a fee recalculated,
    /// a method withdrawn — and what has been typed is not the caller's to replace.
    func testAnUpdateLeavesTypedValuesAlone() {
        let viewModel = PayabliPayInPaymentFlowViewModel(
            component: makeComponent(),
            configuration: PayabliPayInPaymentFlowFormConfiguration(allowedMethods: [.card, .ach])
        )
        type(into: viewModel)

        viewModel.update(
            component: makeComponent(entryPoint: "a-different-entry"),
            configuration: PayabliPayInPaymentFlowFormConfiguration(
                allowedMethods: [.card, .ach],
                defaultMethod: .ach
            )
        )

        XCTAssertEqual(viewModel.cardNumber, "4111 1111 1111 1111")
        XCTAssertEqual(viewModel.cardholderName, "Name On Card Test1")
        XCTAssertEqual(viewModel.cardCvv, "999")
        XCTAssertEqual(viewModel.cardZip, "22039")
        XCTAssertEqual(viewModel.achRouting, "121000248")
        XCTAssertEqual(viewModel.achAccount, "1234567890")
    }

    /// An update carrying nothing new does not republish. A host re-renders on
    /// every state change of its own, so a form that publishes each time
    /// invalidates the view that has just drawn it.
    func testAnUpdateWithNothingNewPublishesNothing() {
        let component = makeComponent()
        let configuration = PayabliPayInPaymentFlowFormConfiguration(allowedMethods: [.card])
        let viewModel = PayabliPayInPaymentFlowViewModel(
            component: component,
            configuration: configuration
        )
        var publishes = 0
        let subscription = viewModel.objectWillChange.sink { _ in publishes += 1 }
        defer { subscription.cancel() }

        viewModel.update(component: component, configuration: configuration)

        XCTAssertEqual(publishes, 0, "a re-render republished the form")

        viewModel.update(
            component: component,
            configuration: PayabliPayInPaymentFlowFormConfiguration(allowedMethods: [.card, .ach])
        )

        XCTAssertEqual(publishes, 1, "a changed configuration did not republish")
    }

    /// Configuration the caller does change reaches the form, so the guard above is
    /// not the update doing nothing at all.
    func testAnUpdateReachesTheConfigurationItCarries() {
        let viewModel = PayabliPayInPaymentFlowViewModel(
            component: makeComponent(),
            configuration: PayabliPayInPaymentFlowFormConfiguration(
                allowedMethods: [.card, .ach],
                defaultMethod: .card
            )
        )
        XCTAssertEqual(viewModel.selectedMethod, .card)

        viewModel.update(
            component: makeComponent(),
            configuration: PayabliPayInPaymentFlowFormConfiguration(
                allowedMethods: [.ach],
                defaultMethod: .ach
            )
        )

        XCTAssertEqual(viewModel.selectedMethod, .ach, "a method the caller withdrew stayed selected")
    }

    // MARK: - What the caller can seed

    /// A customer the caller configures is merged when the form is submitted, and
    /// never written into a field. So a caller replacing it replaces what is sent,
    /// with nothing on screen to compare against or to overwrite.
    func testConfiguredCustomerDataIsMergedRatherThanSeededIntoFields() {
        let viewModel = PayabliPayInPaymentFlowViewModel(
            component: makeComponent(),
            configuration: PayabliPayInPaymentFlowFormConfiguration(allowedMethods: [.card])
        )
        viewModel.firstName = "Typed"

        // Through an update, not the initial build: a configuration carrying a
        // customer arriving mid-entry is the case that could overwrite a field.
        viewModel.update(
            component: makeComponent(),
            configuration: PayabliPayInPaymentFlowFormConfiguration(
                allowedMethods: [.card],
                hiddenValues: PayabliPayInPaymentFlowHiddenValues(
                    customerData: PayabliPayInPaymentFlowCustomerData(
                        billingEmail: "configured@example.com",
                        firstName: "Configured",
                        lastName: "Customer"
                    )
                )
            )
        )

        XCTAssertEqual(viewModel.firstName, "Typed", "a configured customer overwrote a typed field")
        XCTAssertEqual(viewModel.lastName, "", "a configured customer was written into a field")
        XCTAssertEqual(viewModel.billingEmail, "")
    }

    // MARK: -

    private func makeComponent(entryPoint: String = "entry") -> PayabliPayInPaymentFlow {
        PayabliPayInPaymentFlow(
            accessToken: "access-token",
            entryPoint: entryPoint,
            environment: .sandbox
        )
    }

    private func type(into viewModel: PayabliPayInPaymentFlowViewModel) {
        viewModel.cardholderName = "Name On Card Test1"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardCvv = "999"
        viewModel.cardZip = "22039"
        viewModel.achRouting = "121000248"
        viewModel.achAccount = "1234567890"
    }
}
