import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// Each Objective-C bank account value reaches the stored-method request as the value it names.
@MainActor
final class PayInBankAccountCodesObjCTests: XCTestCase {
    private static let stored = """
    {"responseText":"Success","isSuccess":true,"responseData":{"referenceId":"stored-123","resultCode":1,\
    "resultText":"Approved","methodReferenceId":"stored-123"}}
    """

    func testEachAccountTypeIsSentAsItsValue() async throws {
        let expected: [PayabliPayInAccountTypeCode: String] = [.checking: "Checking", .savings: "Savings"]
        XCTAssertEqual(Set(expected.keys), Set(PayabliPayInAccountTypeCode.allCases))

        for (code, value) in expected {
            let method = try await sentMethod(accountType: code)
            XCTAssertEqual(method["achAccountType"] as? String, value, "\(code)")
        }
    }

    func testEachSecCodeIsSentAsItsValueAndUnspecifiedSendsWEB() async throws {
        let expected: [PayabliPayInSecCodeCode: String] = [
            .unspecified: "WEB", .ppd: "PPD", .web: "WEB", .tel: "TEL", .ccd: "CCD", .boc: "BOC"
        ]
        XCTAssertEqual(Set(expected.keys), Set(PayabliPayInSecCodeCode.allCases))

        for (code, value) in expected {
            let method = try await sentMethod(secCode: code)
            XCTAssertEqual(method["achCode"] as? String, value, "\(code)")
        }
    }

    func testEachHolderTypeIsSentAsItsValueAndUnspecifiedSendsNone() async throws {
        let expected: [PayabliPayInAccountHolderTypeCode: String?] = [
            .unspecified: nil, .personal: "personal", .business: "business"
        ]
        XCTAssertEqual(Set(expected.keys), Set(PayabliPayInAccountHolderTypeCode.allCases))

        for (code, value) in expected {
            let method = try await sentMethod(holderType: code)
            XCTAssertEqual(method["achHolderType"] as? String, value, "\(code)")
            XCTAssertEqual(method.keys.contains("achHolderType"), value != nil, "\(code)")
        }
    }

    // An Objective-C enum parameter is a plain integer, so a host can pass a number that names no case.

    func testAnAccountTypeThatNamesNoCaseIsRefusedAndNothingIsSent() async throws {
        try await assertRefused(
            naming: "PayabliPayInAccountTypeCode",
            accountType: unsafeBitCast(7, to: PayabliPayInAccountTypeCode.self)
        )
    }

    func testASecCodeThatNamesNoCaseIsRefusedAndNothingIsSent() async throws {
        try await assertRefused(naming: "PayabliPayInSecCodeCode", secCode: unsafeBitCast(7, to: PayabliPayInSecCodeCode.self))
    }

    func testAHolderTypeThatNamesNoCaseIsRefusedAndNothingIsSent() async throws {
        try await assertRefused(
            naming: "PayabliPayInAccountHolderTypeCode",
            holderType: unsafeBitCast(-1, to: PayabliPayInAccountHolderTypeCode.self)
        )
    }

    // MARK: - Support

    private func assertRefused(
        naming type: String,
        accountType: PayabliPayInAccountTypeCode = .checking,
        secCode: PayabliPayInSecCodeCode = .unspecified,
        holderType: PayabliPayInAccountHolderTypeCode = .unspecified
    ) async throws {
        let transport = MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.stored)
        let bridge = PayabliPayInObjC(component: PayabliPayIn(entryPoint: "entry", environment: .sandbox, transport: transport))

        let error: NSError? = await withCheckedContinuation { continuation in
            bridge.addBankAccount(
                accountNumber: "1111111111",
                routingNumber: "123456780",
                accountType: accountType,
                holderName: "Jane Doe",
                holderType: holderType,
                secCode: secCode,
                deviceId: nil,
                achValidation: false,
                createAnonymous: false,
                forceCustomerCreation: false,
                temporary: false,
                source: nil
            ) { _, error in continuation.resume(returning: error) }
        }

        let refusal = try XCTUnwrap(error)
        XCTAssertEqual(refusal.domain, "com.payabli.payIn")
        XCTAssertEqual(refusal.userInfo["PayabliErrorType"] as? String, PayabliErrorType.validation.rawValue)
        XCTAssertTrue(refusal.localizedDescription.contains(type), refusal.localizedDescription)
        let sent = await transport.requests
        XCTAssertTrue(sent.isEmpty)
    }

    private func sentMethod(
        accountType: PayabliPayInAccountTypeCode = .checking,
        secCode: PayabliPayInSecCodeCode = .unspecified,
        holderType: PayabliPayInAccountHolderTypeCode = .unspecified
    ) async throws -> [String: Any] {
        let transport = MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.stored)
        let bridge = PayabliPayInObjC(component: PayabliPayIn(
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport
        ))

        let error: NSError? = await withCheckedContinuation { continuation in
            bridge.addBankAccount(
                accountNumber: "1111111111",
                routingNumber: "123456780",
                accountType: accountType,
                holderName: "Jane Doe",
                holderType: holderType,
                secCode: secCode,
                deviceId: nil,
                achValidation: false,
                createAnonymous: false,
                forceCustomerCreation: false,
                temporary: false,
                source: nil
            ) { _, error in continuation.resume(returning: error) }
        }
        XCTAssertNil(error)

        let sent = await transport.requests
        let request = try XCTUnwrap(sent.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        return try XCTUnwrap(body["paymentMethod"] as? [String: Any])
    }
}
