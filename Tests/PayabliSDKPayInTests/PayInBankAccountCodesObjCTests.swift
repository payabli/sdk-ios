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

    func testAnAccountTypeThatNamesNoCaseIsRefusedAndNothingIsSent() {
        assertRefused(
            naming: "PayabliPayInAccountTypeCode",
            field: "paymentMethod.achAccountType",
            accountType: unsafeBitCast(7, to: PayabliPayInAccountTypeCode.self)
        )
    }

    func testASecCodeThatNamesNoCaseIsRefusedAndNothingIsSent() {
        assertRefused(
            naming: "PayabliPayInSecCodeCode",
            field: "paymentMethod.achCode",
            secCode: unsafeBitCast(7, to: PayabliPayInSecCodeCode.self)
        )
    }

    func testAHolderTypeThatNamesNoCaseIsRefusedAndNothingIsSent() {
        assertRefused(
            naming: "PayabliPayInAccountHolderTypeCode",
            field: "paymentMethod.achHolderType",
            holderType: unsafeBitCast(-1, to: PayabliPayInAccountHolderTypeCode.self)
        )
    }

    // MARK: - Support

    private func assertRefused(
        naming type: String,
        field: String,
        accountType: PayabliPayInAccountTypeCode = .checking,
        secCode: PayabliPayInSecCodeCode = .unspecified,
        holderType: PayabliPayInAccountHolderTypeCode = .unspecified
    ) {
        XCTAssertThrowsError(
            try PayabliPayInObjC.validated(accountType: accountType, secCode: secCode, holderType: holderType)
        ) { error in
            XCTAssertEqual((error as? PayabliPayInError.InvalidInput)?.field, field)
        }

        XCTAssertNil(
            storeRequest(accountType: accountType, secCode: secCode, holderType: holderType),
            "\(type): a number that names no case builds no request, so nothing can be sent"
        )
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

        let toStore = try XCTUnwrap(storeRequest(accountType: accountType, secCode: secCode, holderType: holderType))
        let error: NSError? = await withCheckedContinuation { continuation in
            bridge.storeMethod(toStore) { _, error in continuation.resume(returning: error) }
        }
        XCTAssertNil(error)

        let sent = await transport.requests
        let request = try XCTUnwrap(sent.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        return try XCTUnwrap(body["paymentMethod"] as? [String: Any])
    }

    private func storeRequest(
        accountType: PayabliPayInAccountTypeCode,
        secCode: PayabliPayInSecCodeCode,
        holderType: PayabliPayInAccountHolderTypeCode
    ) -> PayabliPayInStoreRequestObjC? {
        PayabliPayInStoreRequestObjC.bankAccount(
            accountNumber: "1111111111",
            routingNumber: "123456780",
            accountType: accountType,
            holderName: "Jane Doe",
            holderType: holderType,
            secCode: secCode
        )
    }
}
