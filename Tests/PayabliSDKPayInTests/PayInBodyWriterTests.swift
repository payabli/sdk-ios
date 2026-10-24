@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// The bytes the body writer writes: every method's exact fragment, the splice that joins it, and
/// the wipes that leave nothing of the digits behind.
final class PayInBodyWriterTests: XCTestCase {
    private func cardData(
        number: String = "4111 1111 1111 1111",
        holder: String = "John Doe",
        cvv: String = "123",
        expiry: String = "02/25",
        zip: String = "12345"
    ) -> PayabliPayInCardData {
        PayabliPayInCardData(
            cardNumber: SensitiveDigits.ofString(number),
            expiry: expiry,
            holderName: holder,
            securityCode: SensitiveDigits.ofString(cvv),
            postalCode: zip
        )
    }

    private func bankData(
        account: String = "123456789",
        holder: String = " John Doe ",
        routing: String = "123-456780",
        accountType: PayabliPayInAccountType = .checking,
        holderType: PayabliPayInAccountHolderType? = .personal,
        device: String? = " dev-1 "
    ) -> PayabliPayInBankAccountData {
        PayabliPayInBankAccountData(
            accountNumber: SensitiveDigits.ofString(account),
            accountType: accountType,
            holderName: holder,
            routingNumber: routing,
            secCode: .web,
            holderType: holderType,
            device: device
        )
    }

    private func text(_ bytes: [UInt8]) throws -> String {
        try XCTUnwrap(String(bytes: bytes, encoding: .utf8))
    }

    private func text(_ body: Data) throws -> String {
        try XCTUnwrap(String(bytes: body, encoding: .utf8))
    }

    // MARK: - The transaction routes' fragment

    /// Sorted, the order the transaction body's writer writes every other object: an encoder's order
    /// is not a promise, so the fragment states one. The buffered digits are written raw after the
    /// shared filter, so a spaced entry is sent as its digits.
    func testTheCaptureCardFragmentWritesItsMembersSorted() throws {
        let full = try PayInBodyWriter.captureFragment(.card(PayabliPayInPaymentMethod.Card(
            data: cardData(),
            initiator: " Jane ",
            saveIfSuccess: true
        )))
        XCTAssertEqual(
            try text(full.rawCopy()),
            #"{"cardHolder":"John Doe","cardcvv":"123","cardexp":"02\/25","cardnumber":"4111111111111111","#
                + #""cardzip":"12345","initiator":"Jane","method":"card","saveIfSuccess":true}"#
        )

        let bare = try PayInBodyWriter.captureFragment(.card(PayabliPayInPaymentMethod.Card(
            data: cardData(),
            initiator: nil,
            saveIfSuccess: nil
        )))
        XCTAssertEqual(
            try text(bare.rawCopy()),
            #"{"cardHolder":"John Doe","cardcvv":"123","cardexp":"02\/25","cardnumber":"4111111111111111","cardzip":"12345","method":"card"}"#
        )
    }

    func testTheCaptureBankFragmentWritesItsMembersSorted() throws {
        let full = try PayInBodyWriter.captureFragment(.bankAccount(PayabliPayInPaymentMethod.BankAccount(
            data: bankData()
        )))
        XCTAssertEqual(
            try text(full.rawCopy()),
            #"{"achAccount":"123456789","achAccountType":"Checking","achCode":"WEB","achHolder":"John Doe","achHolderType":"personal","#
                + #""achRouting":"123456780","device":"dev-1","method":"ach"}"#
        )

        let bare = try PayInBodyWriter.captureFragment(.bankAccount(PayabliPayInPaymentMethod.BankAccount(
            data: bankData(accountType: .savings, holderType: nil, device: nil)
        )))
        XCTAssertEqual(
            try text(bare.rawCopy()),
            #"{"achAccount":"123456789","achAccountType":"Savings","achCode":"WEB","achHolder":"John Doe","achRouting":"123456780","method":"ach"}"#
        )
    }

    func testTheCaptureStoredFragmentAlwaysNamesThePayer() throws {
        let fragment = try PayInBodyWriter.captureFragment(.stored(PayabliPayInPaymentMethod.Stored(
            method: .card,
            storedMethodId: " stored-1 "
        )))
        XCTAssertEqual(
            try text(fragment.rawCopy()),
            #"{"initiator":"payor","method":"card","storedMethodId":"stored-1"}"#
        )
    }

    func testTheCaptureCloudFragmentWritesItsOptionalsOnlyWhenPresent() throws {
        let saving = try PayInBodyWriter.captureFragment(.cloudDevice(PayabliPayInPaymentMethod.CloudDevice(
            device: " dev-1 ",
            saveIfSuccess: true
        )))
        XCTAssertEqual(
            try text(saving.rawCopy()),
            #"{"device":"dev-1","method":"cloud","saveIfSuccess":true}"#
        )

        let bare = try PayInBodyWriter.captureFragment(.cloudDevice(PayabliPayInPaymentMethod.CloudDevice(
            device: "dev-1"
        )))
        XCTAssertEqual(
            try text(bare.rawCopy()),
            #"{"device":"dev-1","method":"cloud"}"#
        )
    }

    /// The holder's wire spelling predates this writer and is kept: `achHolder`, not a check-specific
    /// key. This platform and its sibling already disagree there, and this change is not the one to
    /// resolve it.
    func testTheCaptureCheckFragmentNamesItsHolderUnderAchHolder() throws {
        let fragment = try PayInBodyWriter.captureFragment(.check(PayabliPayInPaymentMethod.Check(
            holderName: " John Doe "
        )))
        XCTAssertEqual(
            try text(fragment.rawCopy()),
            #"{"achHolder":"John Doe","method":"check"}"#
        )
    }

    func testTheCaptureCashFragmentCarriesOnlyTheMethod() throws {
        let fragment = try PayInBodyWriter.captureFragment(.cash)
        XCTAssertEqual(
            try text(fragment.rawCopy()),
            #"{"method":"cash"}"#
        )
    }

    // MARK: - The token-storage route's fragment

    /// The token-storage route's own order, not sorted: what that route has always sent.
    func testTheStoreCardFragmentKeepsTheRoutesCallOrder() throws {
        let fragment = try PayInBodyWriter.storeFragment(.card(cardData()))
        XCTAssertEqual(
            try text(fragment.rawCopy()),
            #"{"method":"card","cardexp":"02\/25","cardHolder":"John Doe","cardnumber":"4111111111111111","cardcvv":"123","cardzip":"12345"}"#
        )
    }

    func testTheStoreBankFragmentKeepsTheRoutesCallOrder() throws {
        let full = try PayInBodyWriter.storeFragment(.bankAccount(bankData(holderType: .business)))
        XCTAssertEqual(
            try text(full.rawCopy()),
            #"{"method":"ach","achAccount":"123456789","achAccountType":"Checking","achHolder":"John Doe","#
                + #""achRouting":"123456780","achCode":"WEB","achHolderType":"business","device":"dev-1"}"#
        )

        let bare = try PayInBodyWriter.storeFragment(.bankAccount(bankData(holderType: nil, device: nil)))
        XCTAssertEqual(
            try text(bare.rawCopy()),
            #"{"method":"ach","achAccount":"123456789","achAccountType":"Checking","achHolder":"John Doe","achRouting":"123456780","achCode":"WEB"}"#
        )
    }

    // MARK: - Escaping and refusal

    /// Both quoting styles delegate escaping to a JSON codec rather than hand-rolling it, so a value
    /// carrying a quote, a backslash or a control character arrives decoded exactly as it was given.
    func testBothQuotingStylesEscapeSpecialCharactersAndRoundTrip() throws {
        let holder = #"She said "ok"\ and left"#
        let zip = "12\n34"
        let fragments = [
            try PayInBodyWriter.captureFragment(.card(PayabliPayInPaymentMethod.Card(
                data: cardData(holder: holder, zip: zip)
            ))),
            try PayInBodyWriter.storeFragment(.card(cardData(holder: holder, zip: zip)))
        ]

        for (index, fragment) in fragments.enumerated() {
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(fragment.rawCopy())) as? [String: Any]
            )
            XCTAssertEqual(holder, object["cardHolder"] as? String, "fragment \(index)")
            XCTAssertEqual(zip, object["cardzip"] as? String, "fragment \(index)")
            XCTAssertEqual("02/25", object["cardexp"] as? String, "fragment \(index)")
        }
    }

    /// A digit-shaped character from another script is refused rather than sent as the value it
    /// resembles, in both routes' fragments.
    func testTheWriterRefusesADigitThatIsNotAscii() throws {
        let nonAsciiCard = cardData(number: "٤" + String(repeating: "١", count: 15))
        do {
            _ = try PayInBodyWriter.captureFragment(.card(PayabliPayInPaymentMethod.Card(data: nonAsciiCard)))
            XCTFail("Expected a refusal")
        } catch let PayabliPayInTokenStorageError.invalidInput(message) {
            XCTAssertEqual(message, "Card number contains unsupported characters.")
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        let nonAsciiAccount = bankData(account: String(repeating: "١", count: 13))
        do {
            _ = try PayInBodyWriter.captureFragment(.bankAccount(PayabliPayInPaymentMethod.BankAccount(
                data: nonAsciiAccount
            )))
            XCTFail("Expected a refusal")
        } catch let PayabliPayInTokenStorageError.invalidInput(message) {
            XCTAssertEqual(message, "Account number contains unsupported characters.")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - The splice and the wipes

    func testTheSpliceAddsTheMethodAsTheLastMemberAndConsumesTheFragment() throws {
        let fragment = try PayInBodyWriter.captureFragment(.card(PayabliPayInPaymentMethod.Card(
            data: cardData()
        )))
        XCTAssertFalse(fragment.rawCopy().isEmpty, "the fragment holds its bytes until the splice copies them")

        let body = try PayInBodyWriter.splice(outer: Data(#"{"entryPoint":"entry"}"#.utf8), fragment: fragment)

        XCTAssertEqual(
            try text(body),
            #"{"entryPoint":"entry","paymentMethod":{"cardHolder":"John Doe","cardcvv":"123","cardexp":"02\/25","#
                + #""cardnumber":"4111111111111111","cardzip":"12345","initiator":"payor","method":"card"}}"#
        )
        XCTAssertTrue(fragment.rawCopy().isEmpty, "the splice overwrites the fragment once copied")
    }

    func testTheSpliceTakesNoSeparatorIntoAnEmptyObject() throws {
        let body = try PayInBodyWriter.splice(
            outer: Data("{}".utf8),
            fragment: try PayInBodyWriter.captureFragment(.cash)
        )
        XCTAssertEqual(
            try text(body),
            #"{"paymentMethod":{"method":"cash"}}"#
        )
    }

    func testTheSpliceRefusesAnOuterThatIsNotAnObjectAndStillWipesTheFragment() throws {
        let fragment = try PayInBodyWriter.captureFragment(.card(PayabliPayInPaymentMethod.Card(
            data: cardData()
        )))

        XCTAssertThrowsError(try PayInBodyWriter.splice(outer: Data("[1,2]".utf8), fragment: fragment)) { error in
            guard let error = error as? PayabliGenericError else {
                XCTFail("The refusal is the SDK's own decoding error, not \(error)")
                return
            }
            XCTAssertEqual(error.type, .decodingError)
        }
        XCTAssertTrue(fragment.rawCopy().isEmpty, "the refusal still overwrites the fragment")
    }

    func testAWipedFragmentHoldsNothing() throws {
        let fragment = try PayInBodyWriter.captureFragment(.card(PayabliPayInPaymentMethod.Card(
            data: cardData()
        )))
        XCTAssertFalse(fragment.rawCopy().isEmpty)

        fragment.wipe()
        XCTAssertTrue(fragment.rawCopy().isEmpty)

        fragment.wipe()
        XCTAssertTrue(fragment.rawCopy().isEmpty, "wiping a wiped fragment is not an error")
    }

    func testWipeOverwritesABodyTheRoutesBuilt() {
        var body = Data(#"{"cardnumber":"4111111111111111"}"#.utf8)
        let original = body.count

        PayInBodyWriter.wipe(&body)

        XCTAssertEqual(original, body.count)
        XCTAssertEqual(Array(repeating: 0, count: original), Array(body))
    }
}
