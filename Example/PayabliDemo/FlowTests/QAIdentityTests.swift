import XCTest

/// The one property the whole exercise rests on: two devices in a run never produce the same values.
///
/// The names here are the three phones and the simulator the run uses, spelled as each platform reports them.
final class QAIdentityTests: XCTestCase {
    private let runDevices = ["Google Pixel 7a", "samsung SM-S908U1", "samsung SM-A136U1", "iPhone 17"]

    func testDevicesInARunShareNoValue() {
        let identities = runDevices.map { QAIdentity(label: $0) }

        let reads: [(String, (QAIdentity) -> String)] = [
            ("label", \.label),
            ("slug", \.slug),
            ("holder name", \.holderName),
            ("last name", \.lastName),
            ("customer number", \.customerNumber),
            ("billing email", \.billingEmail),
            ("note", { $0.note("capture") })
        ]

        for (name, read) in reads {
            let values = identities.map(read)
            XCTAssertEqual(values.count, Set(values).count, "two devices answered the same \(name): \(values)")
        }
    }

    func testAnAccountHolderNameCarriesNothingTheStoreRouteRefuses() {
        // Measured on qa: "QA Samsung SM-S908U1" comes back "Bad Request: Account holder name cannot contain
        // special characters", and the same name without the hyphen is stored. Every model code has punctuation
        // in it, so this is every device rather than an unlucky one.
        for identity in runDevices.map({ QAIdentity(label: $0) }) {
            let plain = identity.holderName.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " }
            XCTAssertTrue(plain, "\(identity.holderName) carries something other than a letter, digit or space")
            XCTAssertFalse(identity.holderName.contains("  "), "\(identity.holderName) has a run of spaces")
        }

        XCTAssertEqual(QAIdentity(label: "Samsung SM-S908U1").holderName, "QA Samsung SM S908U1")
    }

    func testSlugIsSafeInACustomerNumberAndAnAddress() {
        for identity in runDevices.map({ QAIdentity(label: $0) }) {
            let allowed = identity.slug.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" }
            XCTAssertTrue(allowed, "\(identity.slug) carries something other than a letter, a digit or a dash")
            XCTAssertFalse(identity.slug.hasPrefix("-"), "\(identity.slug) starts with a dash")
            XCTAssertFalse(identity.slug.hasSuffix("-"), "\(identity.slug) ends with a dash")
        }
    }

    func testANameThatSaysNothingStillNamesSomething() {
        // An empty customer number is a 400 that names no field.
        let identity = QAIdentity(label: "   ")

        XCTAssertEqual(identity.label, "Unknown device")
        XCTAssertEqual(identity.customerNumber, "qa-ios-unknown-device")
    }

    /// Punctuation alone is not blank, and every value a transaction is
    /// attributed by is built from the slug.
    func testANameOfPunctuationAloneIsNamedUnknown() {
        for label in ["---", "!!!", "-", "()", "· ·", "🙂"] {
            let identity = QAIdentity(label: label)

            XCTAssertEqual(identity.label, "Unknown device", "label \(label)")
            XCTAssertEqual(identity.slug, "unknown-device", "label \(label)")
            XCTAssertEqual(identity.customerNumber, "qa-ios-unknown-device", "label \(label)")
            XCTAssertEqual(identity.billingEmail, "qa+unknown-device@example.com", "label \(label)")
        }
    }

    /// An empty slug leaves an identifier beginning with the timestamp.
    func testAnOrderIdentifierFromAPunctuationNameStillNamesTheDevice() {
        let identity = QAIdentity(label: "---")
        let orderId = identity.orderId(at: date(hour: 12, minute: 0, second: 0))

        XCTAssertTrue(orderId.hasPrefix("unknown-device-"), orderId)
        XCTAssertFalse(orderId.hasPrefix("-"), "\(orderId) begins with the timestamp")
    }

    func testAnOrderIdentifierCarriesTheDeviceAndTheSecond() {
        // To the second, because a walk submits several a minute apart.
        let identity = QAIdentity(label: "iPhone 17")
        let noon = date(hour: 12, minute: 0, second: 0)
        let secondLater = date(hour: 12, minute: 0, second: 1)

        XCTAssertEqual(identity.orderId(at: noon), "iphone-17-20260814-120000")
        XCTAssertNotEqual(identity.orderId(at: noon), identity.orderId(at: secondLater))
    }

    /// 2026-08-14 in the current zone, which is what `orderId(at:)` formats in.
    ///
    /// Gregorian explicitly: under another calendar these components name a
    /// different instant, and the assertion above is an exact string. The zone
    /// stays local, because that is the zone the identifier is formatted in.
    private func date(hour: Int, minute: Int, second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 14
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)!
    }
}
