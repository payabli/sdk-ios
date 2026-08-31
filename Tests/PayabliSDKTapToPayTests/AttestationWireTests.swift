@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// What the attestation endpoints are actually sent, decoded from the request.
///
/// Every other suite here asserts what a helper returns. These decode the body that
/// reached the wire, which is the only thing that catches a change in how a value
/// gets from the helper into the request.
final class AttestationWireTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    /// Activation sends the handle the assertion was signed for.
    ///
    /// The binding is read before the challenge and the assertion reloads it after
    /// two suspensions, so an attestation landing in between leaves the body naming
    /// one device and the headers signing for another. Read separately they can
    /// disagree, and a request whose body and signature describe different devices
    /// is refused for a reason neither of them names.
    func testActivationSendsTheHandleTheAssertionWasSignedFor() async throws {
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev_old", keyId: "old_key", in: storage)

        let bodies = BodyBox()
        StubURLProtocol.handler = { request in
            if request.url!.path == "/api/v2/device/taptopay/activate" {
                bodies.append(request.payabliTestBody)
            }
            if request.url!.path == "/api/v2/device/taptopay/challenge" {
                // Enrolled again while the nonce is being rotated, which is the
                // window between the read at the top of the call and the one the
                // assertion makes. Later than this and both reads see one binding.
                try? AttestFixture.seedBinding(
                    entry: "myEntry", deviceId: "dev_new", keyId: "new_key", in: storage
                )
            }
            return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
        }

        let (sut, _, _) = try AttestFixture.makeService(storage: storage)

        try await sut.activateDevice(activationCode: "123456", entry: "myEntry")

        let body = try XCTUnwrap(bodies.values.first)
        let sent = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(body)) as? [String: Any]
        )
        XCTAssertEqual(
            sent["deviceId"] as? String,
            "dev_new",
            "the body named the device read before the assertion, which signed for another"
        )
    }

    /// A 401 answering one binding does not take a binding enrolled since.
    func testAnActivationRefusalLeavesABindingEnrolledSince() async throws {
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev_old", keyId: "old_key", in: storage)

        let refusal = #"{"isSuccess":false,"responseText":"revoked","responseData":{"resultCode":401,"resultText":"revoked"}}"#
        StubURLProtocol.handler = { request in
            if request.url!.path == "/api/v2/device/taptopay/activate" {
                // Enrolled again while the activation request is in flight.
                try? AttestFixture.seedBinding(
                    entry: "myEntry", deviceId: "dev_new", keyId: "new_key", in: storage
                )
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Data(refusal.utf8)
                )
            }
            return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
        }

        let (sut, _, _) = try AttestFixture.makeService(storage: storage)

        do {
            try await sut.activateDevice(activationCode: "123456", entry: "myEntry")
            XCTFail("a refused activation reported success")
        } catch {}

        XCTAssertEqual(
            try sut.binding(for: "myEntry")?.deviceId,
            "dev_new",
            "the binding enrolled while the request was in flight was dropped by a refusal about the older one"
        )
    }

    /// What registration is actually sent, decoded from the request.
    ///
    /// The identifier's own tests say what the helper returns; none of them says
    /// what reaches the wire. A change sending the stored seed instead of the digest,
    /// or putting `deviceName` back, leaves every one of them green while breaking
    /// both things this branch claims about that request.
    func testTheRegisterBodyCarriesTheDigestAndNoDeviceName() async throws {
        let bodies = BodyBox()
        StubURLProtocol.handler = { request in
            if request.url!.path == "/api/v2/device/taptopay/register" {
                bodies.append(request.payabliTestBody)
                return AttestFixture.ok(request, ["deviceId": "dev_1"])
            }
            if request.url!.path == "/api/v2/device/taptopay/challenge" {
                return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            }
            return AttestFixture.ok(request, ["ok": true])
        }

        // The real provider, so this covers the wiring rather than a stand-in.
        let storage = InMemorySecureStorage()
        let (sut, _, _) = try AttestFixture.makeService(
            storage: storage,
            hardwareIdProvider: { try InstallIdentifier.hardwareId(storage: storage, bundleIdentifier: "com.acme.checkout") }
        )

        _ = try await sut.attest(entry: "myEntry", appId: "TEAM.bundle.id")

        let body = try XCTUnwrap(bodies.values.first)
        let sent = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(body)) as? [String: Any]
        )

        XCTAssertNil(sent["deviceName"], "deviceName is back on the wire")

        let hardwareId = try XCTUnwrap(sent["hardwareId"] as? String)
        let seed = try XCTUnwrap(storage.string(forKey: PayabliKeychainKey.installId))
        XCTAssertNotEqual(hardwareId, seed, "the stored seed itself was sent")
        XCTAssertEqual(hardwareId.count, 32)
        XCTAssertTrue(hardwareId.allSatisfy(\.isHexDigit))
        XCTAssertEqual(
            hardwareId,
            try InstallIdentifier.hardwareId(storage: storage, bundleIdentifier: "com.acme.checkout"),
            "what was sent is not what the identifier produces for this install"
        )
    }
}
