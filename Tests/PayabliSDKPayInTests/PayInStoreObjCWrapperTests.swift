import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// A store request object holds the digit buffers its factory built. Each store spends a copy of them, so the
/// same object can be stored again, and the object overwrites its own buffers when it is released.
@MainActor
final class PayInStoreObjCWrapperTests: XCTestCase {
    func testTheSameCardWrapperStoresTwice() async throws {
        let wrapper = PayabliPayInStoreRequestObjC.card(
            cardNumber: "4111111111111111",
            expiryMonth: 2,
            expiryYear: 2030,
            securityCode: "999",
            holderName: "Jane Doe",
            postalCode: "12345"
        )
        try await assertStoresTwice(wrapper, digitLengths: [16, 3])
    }

    func testTheSameBankAccountWrapperStoresTwice() async throws {
        let wrapper = try XCTUnwrap(Self.bankWrapper())
        try await assertStoresTwice(wrapper, digitLengths: [10])
    }

    func testTheWrapperOverwritesItsCardBuffersWhenItIsReleased() {
        let digits = autoreleasepool {
            PayabliPayInStoreRequestObjC.card(
                cardNumber: "4111111111111111",
                expiryMonth: 2,
                expiryYear: 2030,
                securityCode: "999",
                holderName: "Jane Doe",
                postalCode: "12345"
            ).instrument.sensitiveDigits
        }
        XCTAssertEqual(digits.map { $0.rawCopy() }, [Array(repeating: 0, count: 16), Array(repeating: 0, count: 3)])
    }

    func testTheWrapperOverwritesItsAccountNumberWhenItIsReleased() {
        let digits: [SensitiveDigits] = autoreleasepool { Self.bankWrapper()?.instrument.sensitiveDigits ?? [] }
        XCTAssertEqual(digits.map { $0.rawCopy() }, [Array(repeating: 0, count: 10)])
    }

    // MARK: -

    private func assertStoresTwice(
        _ wrapper: PayabliPayInStoreRequestObjC,
        digitLengths: [Int],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let transport = RecordingIdempotencyTransport(body: Self.stored)
        let bridge = PayabliPayInObjC(component: PayInFixture.makeFlow(transport: transport, key: "k1"))

        let first = await store(wrapper, through: bridge)
        let second = await store(wrapper, through: bridge)

        XCTAssertNil(first.1, "the first store failed: \(String(describing: first.1))", file: file, line: line)
        XCTAssertNil(second.1, "the second store failed: \(String(describing: second.1))", file: file, line: line)
        XCTAssertEqual(transport.count, 2, "both stores reached the service", file: file, line: line)
        XCTAssertEqual(
            wrapper.instrument.sensitiveDigits.map(\.length), digitLengths,
            "each store spent its own copy, leaving the wrapper's digits",
            file: file,
            line: line
        )
    }

    private func store(
        _ wrapper: PayabliPayInStoreRequestObjC,
        through bridge: PayabliPayInObjC
    ) async -> (PayabliPayInStoredMethodObjC?, NSError?) {
        await withCheckedContinuation { continuation in
            bridge.storeMethod(wrapper) { method, error in continuation.resume(returning: (method, error)) }
        }
    }

    private static func bankWrapper() -> PayabliPayInStoreRequestObjC? {
        PayabliPayInStoreRequestObjC.bankAccount(
            accountNumber: "1111111111",
            routingNumber: "021000021",
            accountType: .checking,
            holderName: "Jane Doe",
            holderType: .unspecified,
            secCode: .unspecified
        )
    }

    private static let stored = Data("""
    {"responseText":"Success","isSuccess":true,"responseData":{"referenceId":"stored-123","resultCode":1,\
    "resultText":"Approved","methodReferenceId":"stored-123"}}
    """.utf8)
}
