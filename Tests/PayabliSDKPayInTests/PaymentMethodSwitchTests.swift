import Combine
@testable import PayabliSDKPayIn
import XCTest

/// What the payer's own switch between card and bank does to what they typed.
///
/// A value typed under the tab the payer left is never submitted with the other method, and the
/// payer can no longer see it, so the form does not hold it. A field both tabs show is kept.
@MainActor
final class PaymentMethodSwitchTests: XCTestCase {
    func testLeavingCardDropsWhatOnlyTheCardTabShows() {
        let viewModel = makeViewModel()
        typeCard(into: viewModel)

        viewModel.selectedMethod = .bankAccount
        XCTAssertEqual(viewModel.cardNumber, "", "the card number was held after leaving card")
        viewModel.selectedMethod = .card

        XCTAssertEqual(viewModel.cardholderName, "")
        XCTAssertEqual(viewModel.cardNumber, "")
        XCTAssertEqual(viewModel.cardExpiration, "")
        XCTAssertNil(viewModel.cardExpirationMonth)
        XCTAssertNil(viewModel.cardExpirationYear)
        XCTAssertEqual(viewModel.cardCvv, "")
        XCTAssertEqual(viewModel.cardZip, "")
    }

    func testLeavingBankDropsWhatOnlyTheBankTabShows() {
        let viewModel = makeViewModel(defaultMethod: .bankAccount)
        typeBank(into: viewModel)

        viewModel.selectedMethod = .card
        XCTAssertEqual(viewModel.accountNumber, "", "the account number was held after leaving bank")
        viewModel.selectedMethod = .bankAccount

        XCTAssertEqual(viewModel.accountHolder, "")
        XCTAssertEqual(viewModel.routingNumber, "")
        XCTAssertEqual(viewModel.accountNumber, "")
        XCTAssertEqual(viewModel.accountType, .checking)
        XCTAssertEqual(viewModel.accountHolderType, .personal)
    }

    func testAFieldBothTabsShowIsKeptAcrossASwitch() {
        let shared: [PayabliPayInField] = [
            .firstName, .lastName, .customerNumber, .billingEmail, .billingZip, .methodDescription
        ]
        let viewModel = makeViewModel(
            cardFieldOrder: PayabliPayInFormConfiguration.defaultCardFieldOrder + shared,
            bankFieldOrder: PayabliPayInFormConfiguration.defaultBankFieldOrder + shared
        )
        typeCustomer(into: viewModel)

        viewModel.selectedMethod = .bankAccount
        viewModel.selectedMethod = .card

        XCTAssertEqual(viewModel.firstName, "Jane")
        XCTAssertEqual(viewModel.lastName, "Doe")
        XCTAssertEqual(viewModel.customerNumber, "C-100")
        XCTAssertEqual(viewModel.billingEmail, "jane@example.com")
        XCTAssertEqual(viewModel.billingZip, "22039")
        XCTAssertEqual(viewModel.methodDescription, "Rent")
    }

    /// The tab's own layout decides what goes, so a customer field only one tab shows is
    /// that tab's alone.
    func testACustomerFieldOnlyTheLeftTabShowsIsDropped() {
        let viewModel = makeViewModel(
            cardFieldOrder: PayabliPayInFormConfiguration.defaultCardFieldOrder + [.billingEmail, .firstName],
            bankFieldOrder: PayabliPayInFormConfiguration.defaultBankFieldOrder + [.firstName]
        )
        viewModel.billingEmail = "jane@example.com"
        viewModel.firstName = "Jane"

        viewModel.selectedMethod = .bankAccount

        XCTAssertEqual(viewModel.billingEmail, "")
        XCTAssertEqual(viewModel.firstName, "Jane")
    }

    /// The picker reports a tap on the tab already chosen, and that is not a switch.
    func testChoosingTheTabAlreadyChosenDropsNothing() {
        let viewModel = makeViewModel()
        typeCard(into: viewModel)

        viewModel.selectedMethod = .card

        XCTAssertEqual(viewModel.cardNumber, "4111 1111 1111 1111")
        XCTAssertEqual(viewModel.cardCvv, "999")
    }

    /// A switch with nothing typed writes nothing, so it publishes once, for the method itself.
    func testASwitchWithNothingTypedPublishesOnce() {
        let viewModel = makeViewModel()
        var publishes = 0
        let subscription = viewModel.objectWillChange.sink { _ in publishes += 1 }
        defer { subscription.cancel() }

        viewModel.selectedMethod = .bankAccount

        XCTAssertEqual(publishes, 1)
    }

    // MARK: - Helpers

    private func makeViewModel(
        defaultMethod: PayabliPayInMethodType = .card,
        cardFieldOrder: [PayabliPayInField] = PayabliPayInFormConfiguration.defaultCardFieldOrder,
        bankFieldOrder: [PayabliPayInField] = PayabliPayInFormConfiguration.defaultBankFieldOrder
    ) -> PayabliPayInViewModel {
        PayabliPayInViewModel(
            component: flowOnSession(),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.card, .bankAccount],
                defaultMethod: defaultMethod,
                cardFieldOrder: cardFieldOrder,
                bankFieldOrder: bankFieldOrder
            )
        )
    }

    private func typeCard(into viewModel: PayabliPayInViewModel) {
        viewModel.cardholderName = "Name On Card Test1"
        viewModel.cardNumber = "4111111111111111"
        viewModel.selectExpirationMonth(12)
        viewModel.selectExpirationYear(2030)
        viewModel.cardCvv = "999"
        viewModel.cardZip = "22039"
    }

    private func typeBank(into viewModel: PayabliPayInViewModel) {
        viewModel.accountHolder = "Jane Doe"
        viewModel.routingNumber = "121000248"
        viewModel.accountNumber = "1234567890"
        viewModel.accountType = .savings
        viewModel.accountHolderType = .business
    }

    private func typeCustomer(into viewModel: PayabliPayInViewModel) {
        viewModel.firstName = "Jane"
        viewModel.lastName = "Doe"
        viewModel.customerNumber = "C-100"
        viewModel.billingEmail = "jane@example.com"
        viewModel.billingZip = "22039"
        viewModel.methodDescription = "Rent"
    }
}
