import Combine
@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
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
        let viewModel = PayabliPayInViewModel(
            component: makeComponent(),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card, .bankAccount])
        )
        type(into: viewModel)

        viewModel.update(
            component: makeComponent(entryPoint: "a-different-entry"),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.card, .bankAccount],
                defaultMethod: .bankAccount
            )
        )

        XCTAssertEqual(viewModel.cardNumber, "4111 1111 1111 1111")
        XCTAssertEqual(viewModel.cardholderName, "Name On Card Test1")
        XCTAssertEqual(viewModel.cardCvv, "999")
        XCTAssertEqual(viewModel.cardZip, "22039")
        XCTAssertEqual(viewModel.routingNumber, "121000248")
        XCTAssertEqual(viewModel.accountNumber, "1234567890")
    }

    /// An update carrying nothing new does not republish. A host re-renders on
    /// every state change of its own, so a form that publishes each time
    /// invalidates the view that has just drawn it.
    func testAnUpdateWithNothingNewPublishesNothing() {
        let component = makeComponent()
        let configuration = PayabliPayInFormConfiguration(allowedMethods: [.card])
        let viewModel = PayabliPayInViewModel(
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
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card, .bankAccount])
        )

        XCTAssertEqual(publishes, 1, "a changed configuration did not republish")
    }

    /// Configuration the caller does change reaches the form, so the guard above is
    /// not the update doing nothing at all.
    func testAnUpdateReachesTheConfigurationItCarries() {
        let viewModel = PayabliPayInViewModel(
            component: makeComponent(),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.card, .bankAccount],
                defaultMethod: .card
            )
        )
        XCTAssertEqual(viewModel.selectedMethod, .card)

        viewModel.update(
            component: makeComponent(),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.bankAccount],
                defaultMethod: .bankAccount
            )
        )

        XCTAssertEqual(viewModel.selectedMethod, .bankAccount, "a method the caller withdrew stayed selected")
    }

    // MARK: - What the caller can seed

    /// A customer the caller configures is merged when the form is submitted, and
    /// never written into a field. So a caller replacing it replaces what is sent,
    /// with nothing on screen to compare against or to overwrite.
    func testConfiguredCustomerDataIsMergedRatherThanSeededIntoFields() {
        let viewModel = PayabliPayInViewModel(
            component: makeComponent(),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.card],
                cardSections: [Self.customerSection]
            )
        )
        viewModel.firstName = "Typed"

        // Through an update, not the initial build: a configuration carrying a
        // customer arriving mid-entry is the case that could overwrite a field.
        viewModel.update(
            component: makeComponent(),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.card],
                cardSections: [Self.customerSection],
                hiddenValues: PayabliPayInHiddenValues(
                    customerData: PayabliPayInCustomerData(
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

    // MARK: - What the configuration no longer shows

    /// A value typed into a field the update takes away does not reach the service.
    ///
    /// The host can reconfigure the form under a payer mid-entry, and a field the new configuration
    /// does not show is one the payer can no longer see or correct, so what was typed there goes
    /// with the field.
    func testAValueTypedIntoAFieldTheUpdateTakesAwayDoesNotReachTheService() async throws {
        let transport = ReseedTransport(responseBody: Self.storedMethodResponse)
        let component = PayabliPayIn(
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport,
            operation: .storePaymentMethod
        )
        let viewModel = PayabliPayInViewModel(
            component: component,
            configuration: Self.cardConfiguration(showingBillingZip: true)
        )
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "02/28"
        viewModel.cardCvv = "123"
        viewModel.cardZip = "33139"
        viewModel.billingZip = "33139"

        viewModel.update(
            component: component,
            configuration: Self.cardConfiguration(showingBillingZip: false)
        )

        XCTAssertEqual(viewModel.billingZip, "", "a typed value survived its field going")

        _ = try await viewModel.submit()

        let request = try await firstRequest(from: transport)
        let body = try parseBody(request)
        let customer = body["customerData"] as? [String: Any]
        XCTAssertNil(customer?["billingZip"], "a postcode from a field the host took away reached the service")
        let paymentMethod = try XCTUnwrap(body["paymentMethod"] as? [String: Any])
        XCTAssertEqual(
            paymentMethod["cardzip"] as? String,
            "33139",
            "a field the configuration still shows lost its value"
        )
    }

    /// A host-supplied value for a field that is never shown still reaches the service.
    ///
    /// A hidden value is the host's deliberate pass-through for a field the form never draws, so
    /// the drop above touches nothing the payer did not type.
    func testAHostSuppliedValueForAFieldThatIsNeverShownStillReachesTheService() async throws {
        let transport = ReseedTransport(responseBody: Self.storedMethodResponse)
        let component = PayabliPayIn(
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport,
            operation: .storePaymentMethod
        )
        let hiddenValues = PayabliPayInHiddenValues(
            methodDescription: "Host description",
            customerData: PayabliPayInCustomerData(billingZip: "host-33139")
        )
        let viewModel = PayabliPayInViewModel(
            component: component,
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.card],
                hiddenValues: hiddenValues,
                labels: PayabliPayInLabels(title: "Before update")
            )
        )
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "02/28"
        viewModel.cardCvv = "123"
        viewModel.cardZip = "33139"

        // Through an update, so the values the host supplies are carried by the same change that
        // drops typed values, not only by the initial build.
        viewModel.update(
            component: component,
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.card],
                hiddenValues: hiddenValues,
                labels: PayabliPayInLabels(title: "After update")
            )
        )

        _ = try await viewModel.submit()

        let request = try await firstRequest(from: transport)
        let body = try parseBody(request)
        XCTAssertEqual(body["methodDescription"] as? String, "Host description")
        let customer = try XCTUnwrap(body["customerData"] as? [String: Any])
        XCTAssertEqual(customer["billingZip"] as? String, "host-33139")
    }

    /// A field the configuration takes away and returns starts empty.
    ///
    /// The drop reads what the current configuration shows rather than what changed, so a value
    /// that went with its field does not come back with it.
    func testAFieldTheConfigurationTakesAwayAndReturnsStartsEmpty() {
        let component = makeComponent()
        let viewModel = PayabliPayInViewModel(
            component: component,
            configuration: Self.cardConfiguration(showingBillingZip: true)
        )
        viewModel.billingZip = "33139"

        viewModel.update(component: component, configuration: Self.cardConfiguration(showingBillingZip: false))
        XCTAssertEqual(viewModel.billingZip, "", "a typed value survived its field going")

        viewModel.update(component: component, configuration: Self.cardConfiguration(showingBillingZip: true))
        XCTAssertEqual(viewModel.billingZip, "", "a dropped value returned with its field")
    }

    /// An update drops exactly the values whose fields the new configuration no longer shows.
    ///
    /// A field whose method is still offered is not dropped for being on another tab: the payer
    /// reaches its tab and corrects it there, so its value is not held out of sight.
    func testAnUpdateDropsExactlyTheFieldsTheNewConfigurationNoLongerShows() {
        let component = makeComponent()
        let viewModel = PayabliPayInViewModel(
            component: component,
            configuration: Self.bankConfiguration(showingOptionalFields: true)
        )
        viewModel.accountHolder = "Jane Business"
        viewModel.routingNumber = "123456780"
        viewModel.accountNumber = "1111111111"
        viewModel.accountType = .savings
        viewModel.accountHolderType = .business
        viewModel.deviceId = "terminal-1"
        viewModel.methodDescription = "Business account"
        viewModel.firstName = "Jane"
        viewModel.lastName = "Doe"
        viewModel.customerNumber = "cust-1"
        viewModel.billingEmail = "jane@example.com"
        viewModel.billingZip = "33139"

        viewModel.update(component: component, configuration: Self.bankConfiguration(showingOptionalFields: false))

        XCTAssertEqual(viewModel.accountHolder, "Jane Business")
        XCTAssertEqual(viewModel.routingNumber, "123456780")
        XCTAssertEqual(viewModel.accountNumber, "1111111111")
        XCTAssertEqual(viewModel.accountType, .savings)
        XCTAssertEqual(viewModel.accountHolderType, .personal, "a picked value survived its field going")
        XCTAssertEqual(viewModel.deviceId, "", "a typed value survived its field going")
        XCTAssertEqual(viewModel.methodDescription, "", "a typed value survived its field going")
        XCTAssertEqual(viewModel.firstName, "", "a typed value survived its field going")
        XCTAssertEqual(viewModel.lastName, "", "a typed value survived its field going")
        XCTAssertEqual(viewModel.customerNumber, "", "a typed value survived its field going")
        XCTAssertEqual(viewModel.billingEmail, "", "a typed value survived its field going")
        XCTAssertEqual(viewModel.billingZip, "", "a typed value survived its field going")
    }

    // MARK: -

    /// The customer fields the reseed tests type into, shown where the payer can correct them.
    private static let customerSection = PayabliPayInFieldSection(
        title: "Customer",
        fields: [.firstName, .lastName, .billingEmail]
    )

    private static func cardConfiguration(showingBillingZip: Bool) -> PayabliPayInFormConfiguration {
        PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            cardSections: showingBillingZip
                ? [PayabliPayInFieldSection(title: "Customer", fields: [.billingZip])]
                : nil
        )
    }

    private static func bankConfiguration(showingOptionalFields: Bool) -> PayabliPayInFormConfiguration {
        PayabliPayInFormConfiguration(
            allowedMethods: [.bankAccount],
            defaultMethod: .bankAccount,
            bankSections: showingOptionalFields
                ? [
                    PayabliPayInFieldSection(
                        fields: [.accountHolder, .routingNumber, .accountNumber, .accountType, .accountHolderType, .deviceId]
                    ),
                    PayabliPayInFieldSection(
                        title: "Customer",
                        fields: [.methodDescription, .firstName, .lastName, .customerNumber, .billingEmail, .billingZip]
                    )
                ]
                : [
                    PayabliPayInFieldSection(
                        fields: [.accountHolder, .routingNumber, .accountNumber, .accountType]
                    )
                ]
        )
    }

    private static let storedMethodResponse = """
    {
      "responseText": "Success",
      "isSuccess": true,
      "responseData": {
        "referenceId": "stored-reseed",
        "resultCode": 1,
        "resultText": "Approved",
        "customerId": 4440,
        "methodReferenceId": "stored-reseed"
      }
    }
    """

    private func makeComponent(entryPoint: String = "entry") -> PayabliPayIn {
        flowOnSession(
            token: "access-token",
            entryPoint: entryPoint,
            environment: .sandbox
        )
    }

    private func type(into viewModel: PayabliPayInViewModel) {
        viewModel.cardholderName = "Name On Card Test1"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardCvv = "999"
        viewModel.cardZip = "22039"
        viewModel.routingNumber = "121000248"
        viewModel.accountNumber = "1234567890"
    }
}

private actor ReseedTransport: PayabliTransport {
    private(set) var requests: [PayabliRequest] = []
    private let responseBody: String

    init(responseBody: String) {
        self.responseBody = responseBody
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        requests.append(request)
        return PayabliResponse(
            statusCode: 201,
            headers: [:],
            body: Data(responseBody.utf8)
        )
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        throw PayabliGenericError(code: .unknown, reason: "performV2 is not used")
    }
}

private func firstRequest(from transport: ReseedTransport) async throws -> PayabliRequest {
    let requests = await transport.requests
    return try XCTUnwrap(requests.first)
}

private func parseBody(_ request: PayabliRequest) throws -> [String: Any] {
    let body = try XCTUnwrap(request.body)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
}
