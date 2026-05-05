import XCTest
@testable import PayabliSDKPayIn

@MainActor
final class ACHFormViewModelTests: XCTestCase {

    func testPristineFormQuietUntilTouched() {
        let vm = ACHFormViewModel()
        XCTAssertNil(vm.errorMessage(for: .holderName))
        XCTAssertNil(vm.errorMessage(for: .routingNumber))
        XCTAssertNil(vm.errorMessage(for: .accountNumber))
        XCTAssertFalse(vm.isValid)
    }

    func testFullyFilledIsValid() {
        let vm = ACHFormViewModel()
        vm.holderName = "Jane Doe"
        vm.routingNumber = "021000021"
        vm.accountNumber = "123456789"
        XCTAssertTrue(vm.isValid)
    }

    func testRoutingWithInvalidChecksumIsRejected() {
        let vm = ACHFormViewModel()
        vm.holderName = "Jane"
        vm.routingNumber = "123456789"
        vm.accountNumber = "12345"
        XCTAssertFalse(vm.isValid)
    }

    func testMakePayloadAssignsWebAchCode() {
        let vm = ACHFormViewModel()
        vm.holderName = "Jane"
        vm.routingNumber = "021000021"
        vm.accountNumber = "1234567"

        let payload = vm.makePayload()
        XCTAssertEqual(payload.achCode, "WEB")
        XCTAssertEqual(payload.method, "ach")
        XCTAssertEqual(payload.achAccountType, .checking)
        XCTAssertEqual(payload.achHolderType, .personal)
        XCTAssertEqual(payload.achRouting, "021000021")
        XCTAssertEqual(payload.achAccount, "1234567")
    }

    func testAccountAndHolderTypeSelection() {
        let vm = ACHFormViewModel()
        vm.accountType = .savings
        vm.holderType = .business
        vm.holderName = "Acme Corp"
        vm.routingNumber = "021000021"
        vm.accountNumber = "12345"

        let payload = vm.makePayload()
        XCTAssertEqual(payload.achAccountType, .savings)
        XCTAssertEqual(payload.achHolderType, .business)
    }

    // MARK: - Input caps

    func testRoutingCappedAtNineDigits() {
        let vm = ACHFormViewModel()
        vm.routingNumber = "02100002199"
        XCTAssertEqual(vm.routingNumber, "021000021")
    }

    func testRoutingStripsNonDigits() {
        let vm = ACHFormViewModel()
        vm.routingNumber = "021-000-021"
        XCTAssertEqual(vm.routingNumber, "021000021")
    }

    func testAccountCappedAtSeventeenDigits() {
        let vm = ACHFormViewModel()
        vm.accountNumber = "123456789012345678"
        XCTAssertEqual(vm.accountNumber.count, 17)
    }

    func testAccountStripsNonDigits() {
        let vm = ACHFormViewModel()
        vm.accountNumber = "1234-5678"
        XCTAssertEqual(vm.accountNumber, "12345678")
    }

    // MARK: - Customization (strings)

    func testCustomStringsDriveValidationErrors() {
        let vm = ACHFormViewModel()
        vm.strings = ACHFormStrings(
            holderNameError: "Titular requerido",
            routingNumberError: "Ruta invalida",
            accountNumberError: "Cuenta invalida"
        )
        for field in ACHFormViewModel.Field.allCases {
            vm.markTouched(field)
        }

        XCTAssertEqual(vm.errorMessage(for: .holderName), "Titular requerido")
        XCTAssertEqual(vm.errorMessage(for: .routingNumber), "Ruta invalida")
        XCTAssertEqual(vm.errorMessage(for: .accountNumber), "Cuenta invalida")
    }
}
