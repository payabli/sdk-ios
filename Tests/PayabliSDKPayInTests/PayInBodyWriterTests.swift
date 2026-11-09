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
        expiryMonth: Int = 2,
        expiryYear: Int = 2035,
        zip: String = "12345"
    ) -> PayabliPayInCardData {
        PayabliPayInCardData(
            cardNumber: SensitiveDigits.ofString(number),
            expiryMonth: expiryMonth,
            expiryYear: expiryYear,
            securityCode: SensitiveDigits.ofString(cvv),
            holderName: holder,
            postalCode: zip
        )
    }

    private func bankData(
        account: String = "123456789",
        holder: String = " John Doe ",
        routing: String = "123-456780",
        accountType: PayabliPayInAccountType = .checking,
        holderType: PayabliPayInAccountHolderType? = .personal
    ) -> PayabliPayInBankAccountData {
        PayabliPayInBankAccountData(
            accountNumber: SensitiveDigits.ofString(account),
            routingNumber: routing,
            accountType: accountType,
            holderName: holder,
            holderType: holderType,
            secCode: .web
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
            #"{"cardHolder":"John Doe","cardcvv":"123","cardexp":"02\/35","cardnumber":"4111111111111111","#
                + #""cardzip":"12345","initiator":"Jane","method":"card","saveIfSuccess":true}"#
        )

        let bare = try PayInBodyWriter.captureFragment(.card(PayabliPayInPaymentMethod.Card(
            data: cardData(),
            initiator: nil,
            saveIfSuccess: nil
        )))
        XCTAssertEqual(
            try text(bare.rawCopy()),
            #"{"cardHolder":"John Doe","cardcvv":"123","cardexp":"02\/35","cardnumber":"4111111111111111","cardzip":"12345","method":"card"}"#
        )
    }

    func testTheCaptureBankFragmentWritesItsMembersSorted() throws {
        let full = try PayInBodyWriter.captureFragment(.bankAccount(PayabliPayInPaymentMethod.BankAccount(
            data: bankData()
        )))
        XCTAssertEqual(
            try text(full.rawCopy()),
            #"{"achAccount":"123456789","achAccountType":"Checking","achCode":"WEB","achHolder":"John Doe","achHolderType":"personal","#
                + #""achRouting":"123456780","method":"ach"}"#
        )

        let bare = try PayInBodyWriter.captureFragment(.bankAccount(PayabliPayInPaymentMethod.BankAccount(
            data: bankData(accountType: .savings, holderType: nil)
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

    /// A check names its holder under `achHolder`, the key the account methods use, not a check-specific one.
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
            #"{"method":"card","cardexp":"02\/35","cardHolder":"John Doe","cardnumber":"4111111111111111","cardcvv":"123","cardzip":"12345"}"#
        )
    }

    func testTheStoreBankFragmentKeepsTheRoutesCallOrder() throws {
        let full = try PayInBodyWriter.storeFragment(.bankAccount(bankData(holderType: .business)))
        XCTAssertEqual(
            try text(full.rawCopy()),
            #"{"method":"ach","achAccount":"123456789","achAccountType":"Checking","achHolder":"John Doe","#
                + #""achRouting":"123456780","achCode":"WEB","achHolderType":"business"}"#
        )

        let bare = try PayInBodyWriter.storeFragment(.bankAccount(bankData(holderType: nil)))
        XCTAssertEqual(
            try text(bare.rawCopy()),
            #"{"method":"ach","achAccount":"123456789","achAccountType":"Checking","achHolder":"John Doe","achRouting":"123456780","achCode":"WEB"}"#
        )
    }

    // MARK: - Escaping and refusal

    /// Both quoting styles reach the codec's escaping, so a value carrying a quote, a backslash or a
    /// control character arrives decoded exactly as it was given.
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
            XCTAssertEqual("02/35", object["cardexp"] as? String, "fragment \(index)")
        }
    }

    /// A digit-shaped character from another script is refused in both routes' fragments.
    func testTheWriterRefusesADigitThatIsNotAscii() throws {
        let nonAsciiCard = cardData(number: "٤" + String(repeating: "١", count: 15))
        do {
            _ = try PayInBodyWriter.captureFragment(.card(PayabliPayInPaymentMethod.Card(data: nonAsciiCard)))
            XCTFail("Expected a refusal")
        } catch let refusal as PayabliPayInError.InvalidInput {
            XCTAssertEqual(refusal.field, PayInFieldPath.method(.cardnumber))
            XCTAssertEqual(refusal.reason, "Card number contains unsupported characters.")
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        let nonAsciiAccount = bankData(account: String(repeating: "١", count: 13))
        do {
            _ = try PayInBodyWriter.captureFragment(.bankAccount(PayabliPayInPaymentMethod.BankAccount(
                data: nonAsciiAccount
            )))
            XCTFail("Expected a refusal")
        } catch let refusal as PayabliPayInError.InvalidInput {
            XCTAssertEqual(refusal.field, PayInFieldPath.method(.achAccount))
            XCTAssertEqual(refusal.reason, "Account number contains unsupported characters.")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - The splice and the wipes

    func testTheSpliceAddsTheMethodAsTheLastMemberAndConsumesTheFragment() throws {
        let fragment = try PayInBodyWriter.captureFragment(.card(PayabliPayInPaymentMethod.Card(
            data: cardData()
        )))
        let length = fragment.rawCopy().count
        XCTAssertGreaterThan(length, 0, "the fragment holds its bytes until the splice copies them")

        let body = try PayInBodyWriter.splice(outer: Data(#"{"entryPoint":"entry"}"#.utf8), fragment: fragment)

        XCTAssertEqual(
            try text(body),
            #"{"entryPoint":"entry","paymentMethod":{"cardHolder":"John Doe","cardcvv":"123","cardexp":"02\/35","#
                + #""cardnumber":"4111111111111111","cardzip":"12345","initiator":"payor","method":"card"}}"#
        )
        XCTAssertEqual(fragment.rawCopy(), zeros(length), "the splice overwrites the fragment once copied")
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
        let length = fragment.rawCopy().count
        XCTAssertGreaterThan(length, 0)

        XCTAssertThrowsError(try PayInBodyWriter.splice(outer: Data("[1,2]".utf8), fragment: fragment)) { error in
            guard let error = error as? PayabliGenericError else {
                XCTFail("The refusal is the SDK's own decoding error, not \(error)")
                return
            }
            XCTAssertEqual(error.type, .decodingError)
        }
        XCTAssertEqual(fragment.rawCopy(), zeros(length), "the refusal still overwrites the fragment")
    }

    func testAWipedFragmentHoldsOnlyZeros() throws {
        let fragment = try PayInBodyWriter.captureFragment(.card(PayabliPayInPaymentMethod.Card(
            data: cardData()
        )))
        let length = fragment.rawCopy().count
        XCTAssertGreaterThan(length, 0)

        fragment.wipe()
        XCTAssertEqual(fragment.rawCopy(), zeros(length))

        fragment.wipe()
        XCTAssertEqual(fragment.rawCopy(), zeros(length), "wiping a wiped fragment is not an error")
    }

    func testFinishingABufferReturnsTheBytesAndLeavesItsStorageZeroed() {
        var buffer = ByteBuffer()
        buffer.write(Array("4111111111111111".utf8))

        XCTAssertEqual(buffer.finishAndWipe(), Array("4111111111111111".utf8))
        XCTAssertEqual(buffer.rawStorage(), zeros(buffer.rawStorage().count))
    }

    func testWipingABufferZeroesItsStorage() {
        var buffer = ByteBuffer()
        buffer.write(Array("4111111111111111".utf8))
        XCTAssertTrue(buffer.rawStorage().contains(0x34), "the storage holds the digits before the wipe")

        buffer.wipe()
        XCTAssertEqual(buffer.rawStorage(), zeros(buffer.rawStorage().count))
    }

    func testAGrownBufferKeepsItsBytesAndZeroesOnFinish() {
        var buffer = ByteBuffer()
        let initialCapacity = buffer.rawStorage().count
        let digits = Array(repeating: UInt8(0x39), count: initialCapacity + 1)
        buffer.write(digits)
        XCTAssertGreaterThan(buffer.rawStorage().count, initialCapacity, "the write grew the storage")

        XCTAssertEqual(buffer.finishAndWipe(), digits)
        XCTAssertEqual(buffer.rawStorage(), zeros(buffer.rawStorage().count))
    }

    private func zeros(_ count: Int) -> [UInt8] {
        Array(repeating: 0, count: count)
    }

    func testWipeOverwritesABodyTheRoutesBuilt() {
        var body = Data(#"{"cardnumber":"4111111111111111"}"#.utf8)
        let original = body.count

        PayInBodyWriter.wipe(&body)

        XCTAssertEqual(original, body.count)
        XCTAssertEqual(Array(repeating: 0, count: original), Array(body))
    }

    func testTheBodyOverwritesItsBytesWhenThePlatformReleasesThem() throws {
        let note = ReleaseNote()

        let sent = try sendTheBodyThePlatformHolds(note)

        XCTAssertEqual(
            sent.routeWiped, Array(repeating: 0, count: sent.count),
            "the route's copy is overwritten at its exit"
        )
        XCTAssertTrue(
            sent.platformWindow.contains("4111111111111111"),
            "the platform-held allocation still carries the body until its release"
        )
        XCTAssertEqual(
            note.count, sent.count,
            "the release ran once the last holder was dropped"
        )
        XCTAssertEqual(
            note.bytes, Array(repeating: 0, count: sent.count),
            "the release overwrites the bytes before the free"
        )
    }

    /// The send's own shape: the platform keeps the body it was given, the route overwrites its
    /// copy once the transport returns, and every holder is then dropped — which is when the
    /// allocation's own overwrite runs.
    private func sendTheBodyThePlatformHolds(_ note: ReleaseNote) throws
        -> (routeWiped: [UInt8], platformWindow: String, count: Int)
    {
        let fragment = try PayInBodyWriter.captureFragment(.card(PayabliPayInPaymentMethod.Card(
            data: cardData()
        )))
        let body = try PayInBodyWriter.splice(
            outer: Data(#"{"entryPoint":"entry"}"#.utf8),
            fragment: fragment,
            releaseNoted: note.record
        )
        let platformHeld = body
        var routeCopy = body
        PayInBodyWriter.wipe(&routeCopy)
        return (Array(routeCopy), try text(platformHeld), body.count)
        // The holders die here: the last release runs the deallocator, which overwrites before freeing.
    }

    func testFormattingTheWorkingBufferPrintsNoDigits() {
        var buffer = ByteBuffer()
        buffer.write(Array("4111111111111111".utf8))

        XCTAssertEqual("ByteBuffer(size=16)", String(describing: buffer))
        XCTAssertEqual(String(describing: buffer), String(reflecting: buffer))
    }

    func testReflectingTheWorkingBufferReachesNoDigits() {
        var buffer = ByteBuffer()
        buffer.write(Array("4111111111111111".utf8))
        var dumped = ""
        dump(buffer, to: &dumped)

        XCTAssertFalse(Mirror(reflecting: buffer).children.contains { $0.value is [UInt8] })
        XCTAssertTrue(dumped.contains("size: 16"), "the buffer dumps as its written count")
        XCTAssertFalse(dumped.contains("- 52"), "the first card digit is not dumped as its byte")
    }

    func testReflectingAFragmentReachesNoDigits() {
        let fragment = PayInMethodFragment(Array("4111111111111111".utf8))
        var dumped = ""
        dump(fragment, to: &dumped)

        XCTAssertFalse(Mirror(reflecting: fragment).children.contains { $0.value is [UInt8] })
        XCTAssertTrue(dumped.contains("count: 16"), "the fragment dumps as its byte count")
        XCTAssertFalse(dumped.contains("- 52"), "the first card digit is not dumped as its byte")
    }
}

/// Reads a body at its release, after the overwrite and before the free: the last holder is gone
/// by then, so the bytes this hands back are the only view of the allocation left.
private final class ReleaseNote: @unchecked Sendable {
    private let lock = NSLock()
    private var bytesAtRelease: [UInt8] = []
    private var releaseCount = -1

    var bytes: [UInt8] {
        lock.withLock { bytesAtRelease }
    }

    var count: Int {
        lock.withLock { releaseCount }
    }

    func record(_ pointer: UnsafeRawPointer, _ count: Int) {
        lock.withLock {
            bytesAtRelease = Array(UnsafeRawBufferPointer(start: pointer, count: count))
            releaseCount = count
        }
    }
}
