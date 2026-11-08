@testable import PayabliSDKPayIn
import XCTest

/// Each Objective-C bank account value reaches the payment request as the value it names.
final class PayInRequestBankAccountObjCTests: XCTestCase {
    func testEachAccountTypeIsSentAsItsValue() throws {
        let expected: [PayabliPayInAccountTypeCode: String] = [.checking: "Checking", .savings: "Savings"]
        XCTAssertEqual(Set(expected.keys), Set(PayabliPayInAccountTypeCode.allCases))

        for (code, value) in expected {
            let method = try sentMethod(accountType: code)
            XCTAssertEqual(method["achAccountType"] as? String, value, "\(code)")
        }
    }

    func testEachSecCodeIsSentAsItsValueAndUnspecifiedSendsWEB() throws {
        let expected: [PayabliPayInSecCodeCode: String] = [
            .unspecified: "WEB", .ppd: "PPD", .web: "WEB", .tel: "TEL", .ccd: "CCD", .boc: "BOC"
        ]
        XCTAssertEqual(Set(expected.keys), Set(PayabliPayInSecCodeCode.allCases))

        for (code, value) in expected {
            let method = try sentMethod(secCode: code)
            XCTAssertEqual(method["achCode"] as? String, value, "\(code)")
        }
    }

    func testEachHolderTypeIsSentAsItsValueAndUnspecifiedSendsNone() throws {
        let expected: [PayabliPayInAccountHolderTypeCode: String?] = [
            .unspecified: nil, .personal: "personal", .business: "business"
        ]
        XCTAssertEqual(Set(expected.keys), Set(PayabliPayInAccountHolderTypeCode.allCases))

        for (code, value) in expected {
            let method = try sentMethod(holderType: code)
            XCTAssertEqual(method["achHolderType"] as? String, value, "\(code)")
            XCTAssertEqual(method.keys.contains("achHolderType"), value != nil, "\(code)")
        }
    }

    // An Objective-C enum parameter is a plain integer, so a host can pass a number that names no case.

    func testAnAccountTypeThatNamesNoCaseBuildsNoRequest() {
        XCTAssertNil(request(accountType: unsafeBitCast(7, to: PayabliPayInAccountTypeCode.self)))
    }

    func testASecCodeThatNamesNoCaseBuildsNoRequest() {
        XCTAssertNil(request(secCode: unsafeBitCast(7, to: PayabliPayInSecCodeCode.self)))
    }

    func testAHolderTypeThatNamesNoCaseBuildsNoRequest() {
        XCTAssertNil(request(holderType: unsafeBitCast(-1, to: PayabliPayInAccountHolderTypeCode.self)))
    }

    // MARK: - Support

    private func request(
        accountType: PayabliPayInAccountTypeCode = .checking,
        secCode: PayabliPayInSecCodeCode = .unspecified,
        holderType: PayabliPayInAccountHolderTypeCode = .unspecified
    ) -> PayabliPayInRequestObjC? {
        PayabliPayInRequestObjC.bankAccount(
            accountNumber: "1111111111",
            routingNumber: "123456780",
            accountType: accountType,
            holderName: "Jane Doe",
            holderType: holderType,
            secCode: secCode,
            totalAmount: 10
        )
    }

    private func sentMethod(
        accountType: PayabliPayInAccountTypeCode = .checking,
        secCode: PayabliPayInSecCodeCode = .unspecified,
        holderType: PayabliPayInAccountHolderTypeCode = .unspecified
    ) throws -> [String: Any] {
        let wrapper = try XCTUnwrap(request(accountType: accountType, secCode: secCode, holderType: holderType))
        let fragment = try PayInBodyWriter.captureFragment(wrapper.toSwift().paymentMethod)
        let json = try JSONSerialization.jsonObject(with: Data(fragment.rawCopy()))
        return try XCTUnwrap(json as? [String: Any])
    }
}
