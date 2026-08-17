@testable import PayabliSDKTapToPay
import XCTest

/// `redactedFieldSummary` is what the charge path logs in place of the customer
/// record. The guarantee is that it names which fields were set and carries no
/// value from any of them.
final class CustomerFieldRedactionTests: XCTestCase {
    /// Distinct from every field name, so a value found in the summary cannot be
    /// the field's own label.
    private static let values = (1 ... 20).map { "zzsentinel\($0)" }
    private static let customerId = 987_654_321

    private static func populated() -> PayabliTTPCustomerData {
        let v = values
        return PayabliTTPCustomerData(
            firstName: v[0],
            lastName: v[1],
            customerNumber: v[2],
            email: v[3],
            phone: v[4],
            customerId: customerId,
            company: v[5],
            billingAddress1: v[6],
            billingAddress2: v[7],
            billingCity: v[8],
            billingState: v[9],
            billingZip: v[10],
            billingCountry: v[11],
            billingPhone: v[12],
            billingEmail: v[13],
            shippingAddress1: v[14],
            shippingAddress2: v[15],
            shippingCity: v[16],
            shippingState: v[17],
            shippingZip: v[18],
            shippingCountry: v[19]
        )
    }

    func testNoCustomerValueReachesTheSummary() {
        let summary = Self.populated().redactedFieldSummary

        for value in Self.values {
            XCTAssertFalse(
                summary.contains(value),
                "\(value) reached the log line: \(summary)"
            )
        }
        XCTAssertFalse(
            summary.contains(String(Self.customerId)),
            "customerId reached the log line: \(summary)"
        )
    }

    func testEveryFieldOfAPopulatedCustomerRendersRedacted() {
        let summary = Self.populated().redactedFieldSummary

        XCTAssertEqual(
            summary.components(separatedBy: "[REDACTED]").count - 1,
            21,
            "every field is set, so each renders redacted: \(summary)"
        )
        XCTAssertFalse(summary.contains("[nil]"), summary)
    }

    func testAnUnsetFieldIsDistinguishedFromASetOne() {
        let summary = PayabliTTPCustomerData(firstName: "Ada").redactedFieldSummary

        XCTAssertTrue(summary.contains("firstName=[REDACTED]"), summary)
        XCTAssertTrue(summary.contains("lastName=[nil]"), summary)
        XCTAssertFalse(summary.contains("Ada"), summary)
    }

    func testEveryFieldIsNamed() {
        let summary = Self.populated().redactedFieldSummary

        let names = [
            "firstName", "lastName", "customerNumber", "customerId", "company",
            "email", "phone",
            "billing.address1", "billing.address2", "billing.city",
            "billing.state", "billing.zip", "billing.country",
            "billing.email", "billing.phone",
            "shipping.address1", "shipping.address2", "shipping.city",
            "shipping.state", "shipping.zip", "shipping.country"
        ]
        for name in names {
            XCTAssertTrue(summary.contains("\(name)="), "\(name) is missing: \(summary)")
        }
    }
}
