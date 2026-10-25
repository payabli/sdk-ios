@testable import PayabliSDKPayIn
import XCTest

/// A request meets `String(describing:)` in assertion failures and diagnostic output, so the request
/// family's descriptions print kinds and flags: every value a payer entered stays out, on the two
/// requests a host builds and on each type they carry.
final class PayabliPayInRequestDescriptionTests: XCTestCase {
    func testDescribingACardStoreRequestExposesNoneOfItsValues() {
        let request = PayabliPayInStoreRequest(
            instrument: .card(Self.enteredCard),
            options: PayabliPayInTokenStorageOptions(
                customerData: Self.payer,
                methodDescription: Self.methodDescription
            )
        )

        let description = String(describing: request)

        for value in Self.cardValues + Self.payerValues + [Self.methodDescription] {
            XCTAssertFalse(
                description.contains(value),
                "the description carries \"\(value)\""
            )
        }
        XCTAssertTrue(description.contains("PayabliPayInStoreRequest(instrument: PayabliPayInMethodInput.card"))
    }

    func testDescribingABankStoreRequestExposesNoneOfItsValues() {
        let request = PayabliPayInStoreRequest(
            instrument: .bankAccount(Self.enteredBankAccount),
            options: PayabliPayInTokenStorageOptions(
                customerData: Self.payer,
                methodDescription: Self.methodDescription
            )
        )

        let description = String(describing: request)

        for value in Self.bankValues + Self.payerValues + [Self.methodDescription] {
            XCTAssertFalse(
                description.contains(value),
                "the description carries \"\(value)\""
            )
        }
        XCTAssertTrue(description.contains("PayabliPayInStoreRequest(instrument: PayabliPayInMethodInput.bankAccount"))
    }

    func testDescribingAChargeRequestExposesNoneOfItsValues() {
        let request = PayabliPayInRequest(
            paymentMethod: .card(PayabliPayInPaymentMethod.Card(data: Self.enteredCard, initiator: "payor")),
            options: PayabliPayInRequestConfiguration(
                paymentDetails: Self.details,
                customerData: Self.payer,
                orderDescription: Self.methodDescription
            )
        )

        let description = String(describing: request)

        for value in Self.cardValues + Self.payerValues + Self.detailsValues + [Self.methodDescription] {
            XCTAssertFalse(
                description.contains(value),
                "the description carries \"\(value)\""
            )
        }
        XCTAssertTrue(description.contains("PayabliPayInRequest(paymentMethod: PayabliPayInPaymentMethod.card"))
    }

    func testReflectingAStoreRequestExposesNoneOfItsValues() {
        let request = PayabliPayInStoreRequest(
            instrument: .card(Self.enteredCard),
            options: PayabliPayInTokenStorageOptions(customerData: Self.payer)
        )

        let reflection = String(reflecting: request)

        for value in Self.cardValues + Self.payerValues {
            XCTAssertFalse(
                reflection.contains(value),
                "the reflection carries \"\(value)\""
            )
        }
    }

    func testDescribingTheEnteredInstrumentDataExposesNoPayerValues() {
        for value in Self.cardValues {
            XCTAssertFalse(
                String(describing: Self.enteredCard).contains(value),
                "the card data's description carries \"\(value)\""
            )
        }
        for value in Self.bankValues {
            XCTAssertFalse(
                String(describing: Self.enteredBankAccount).contains(value),
                "the bank data's description carries \"\(value)\""
            )
        }

        XCTAssertEqual(String(describing: PayabliPayInMethodInput.card(Self.enteredCard)), "PayabliPayInMethodInput.card")
        XCTAssertEqual(
            String(describing: PayabliPayInMethodInput.bankAccount(Self.enteredBankAccount)),
            "PayabliPayInMethodInput.bankAccount"
        )
    }

    func testDescribingAPaymentMethodsCasesExposesNoMethodValues() {
        let cases = [
            PayabliPayInPaymentMethod.card(PayabliPayInPaymentMethod.Card(
                data: Self.enteredCard,
                initiator: "payor",
                saveIfSuccess: true
            )),
            PayabliPayInPaymentMethod.bankAccount(PayabliPayInPaymentMethod.BankAccount(data: Self.enteredBankAccount)),
            PayabliPayInPaymentMethod.stored(PayabliPayInPaymentMethod.Stored(
                method: .card,
                storedMethodId: Self.storedMethodId
            )),
            PayabliPayInPaymentMethod.cloudDevice(PayabliPayInPaymentMethod.CloudDevice(device: Self.device)),
            PayabliPayInPaymentMethod.check(PayabliPayInPaymentMethod.Check(holderName: "Jane Doe")),
            PayabliPayInPaymentMethod.cash
        ]

        for method in cases {
            let description = String(describing: method)
            for value in Self.cardValues + Self.bankValues + [Self.storedMethodId, Self.device] {
                XCTAssertFalse(
                    description.contains(value),
                    "\(description) carries \"\(value)\""
                )
            }
        }
    }

    func testDescribingTheOptionsExposesNoPayerValues() {
        for value in Self.payerValues {
            XCTAssertFalse(
                String(describing: Self.payer).contains(value),
                "the customer data's description carries \"\(value)\""
            )
        }
        for value in Self.detailsValues {
            XCTAssertFalse(
                String(describing: Self.details).contains(value),
                "the payment details' description carries \"\(value)\""
            )
        }
        for value in Self.payerValues + [Self.methodDescription] {
            XCTAssertFalse(
                String(describing: PayabliPayInTokenStorageOptions(
                    customerData: Self.payer,
                    vendorData: PayabliPayInVendorData(vendorId: 4, vendorNumber: "4781"),
                    methodDescription: Self.methodDescription
                )).contains(value),
                "the storage options' description carries \"\(value)\""
            )
        }
        for value in Self.payerValues + Self.detailsValues + [Self.methodDescription] {
            XCTAssertFalse(
                String(describing: PayabliPayInRequestConfiguration(
                    paymentDetails: Self.details,
                    customerData: Self.payer,
                    orderDescription: Self.methodDescription
                )).contains(value),
                "the request configuration's description carries \"\(value)\""
            )
        }
    }

    // MARK: - Fixtures

    private static let enteredCard = PayabliPayInCardData(
        cardNumber: "4111111111111111",
        expiration: "02/30",
        cardholderName: "Jane Doe",
        cvv: "1234",
        billingZip: "33139"
    )

    private static let enteredBankAccount = PayabliPayInBankAccountData(
        accountNumber: "9876543210",
        accountType: .checking,
        holderName: "Richard Roe",
        routingNumber: "021000021"
    )

    private static let payer = PayabliPayInCustomerData(
        billingEmail: "ada@example.com",
        firstName: "Ada",
        lastName: "Lovelace"
    )

    private static let details = PayabliPayInPaymentDetails(
        totalAmount: 15.25,
        serviceFee: 1.5,
        currency: "USD"
    )

    private static let methodDescription = "House account"
    private static let storedMethodId = "stm_4111"
    private static let device = "device-99"

    private static var cardValues: [String] {
        ["4111111111111111", "02/30", "Jane Doe", "1234", "33139"]
    }

    private static var bankValues: [String] {
        ["9876543210", "Richard Roe", "021000021"]
    }

    private static var payerValues: [String] {
        ["Ada", "Lovelace", "ada@example.com"]
    }

    private static var detailsValues: [String] {
        ["15.25", "1.5", "USD"]
    }
}
