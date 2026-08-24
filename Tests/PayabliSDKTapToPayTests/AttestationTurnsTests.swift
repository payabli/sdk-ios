@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// Two callers, one entry point.
///
/// Attestation is serialized per entry point across every service in the process,
/// and each caller then decides from its own store. These are the cases that
/// distinguish waiting for a turn from being handed the previous caller's answer.
final class AttestationTurnsTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    /// App Attest issues a fresh key on every call, so two attestations for one
    /// entry point mint two keys and register two devices, leaving the paypoint with
    /// a device no binding names. A second caller takes the first's answer.
    func testTwoAttestationsForOneEntryPointRegisterOneDevice() async throws {
        let pathsBox = PathsBox()
        StubURLProtocol.handler = { request in
            pathsBox.append(request.url!.path)
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    AttestFixture.envelope(responseData: ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
                )
            case "/api/v2/device/taptopay/register":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    AttestFixture.envelope(responseData: ["deviceId": "dev_1"])
                )
            default:
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    AttestFixture.envelope(responseData: ["ok": true])
                )
            }
        }

        // Two services over one Keychain namespace, which is what a host talking to
        // one paypoint from two places builds.
        let storage = InMemorySecureStorage()
        let (first, firstAttestor, _) = AttestFixture.makeService(storage: storage)
        let (second, secondAttestor, _) = AttestFixture.makeService(storage: storage)

        async let a = first.attest(entry: "myEntry", appId: "TEAM.bundle.id")
        async let b = second.attest(entry: "myEntry", appId: "TEAM.bundle.id")
        let results = try await [a, b]

        XCTAssertEqual(results[0].deviceId, results[1].deviceId, "the two callers hold different devices")
        XCTAssertEqual(
            firstAttestor.generateKeyCalls + secondAttestor.generateKeyCalls,
            1,
            "both callers minted a key, so each registered its own device"
        )
        XCTAssertEqual(
            pathsBox.values.filter { $0 == "/api/v2/device/taptopay/register" }.count,
            1,
            "the paypoint was registered twice and one device has no binding naming it"
        )
        XCTAssertEqual(try first.allBindings().bindings.count, 1)
    }

    /// The gate holds callers that arrive while an attempt is running. This is the
    /// one that arrives just after it ends: its warm check ran before the binding
    /// existed, so without a read inside the gate it registers a second device for
    /// a paypoint that now has one.
    func testAnAttestationAfterAnotherFinishedRegistersNoSecondDevice() async throws {
        let pathsBox = PathsBox()
        StubURLProtocol.handler = { request in
            pathsBox.append(request.url!.path)
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    AttestFixture.envelope(responseData: ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
                )
            case "/api/v2/device/taptopay/register":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    AttestFixture.envelope(responseData: ["deviceId": "dev_1"])
                )
            default:
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    AttestFixture.envelope(responseData: ["ok": true])
                )
            }
        }

        // Two services over one store, as two facades for one paypoint are.
        let storage = InMemorySecureStorage()
        let (first, firstAttestor, _) = AttestFixture.makeService(storage: storage)
        let (second, secondAttestor, _) = AttestFixture.makeService(storage: storage)

        // Sequential, so the second is never inside the gate with the first. Its
        // caller decided to attest before the first had written anything.
        let a = try await first.attest(entry: "myEntry", appId: "TEAM.bundle.id")
        let b = try await second.attest(entry: "myEntry", appId: "TEAM.bundle.id")

        XCTAssertEqual(a.deviceId, b.deviceId, "the second attempt registered its own device")
        XCTAssertEqual(
            pathsBox.values.filter { $0 == "/api/v2/device/taptopay/register" }.count,
            1,
            "the paypoint was registered twice and one device has no binding naming it"
        )
        XCTAssertEqual(secondAttestor.generateKeyCalls, 0, "the second attempt minted a key it did not need")
        XCTAssertEqual(firstAttestor.generateKeyCalls, 1)
        XCTAssertEqual(try first.allBindings().bindings.count, 1)
    }

    /// A binding whose key the platform no longer holds does not answer for a new
    /// attempt: the read inside the gate asks the key, as the warm path does.
    func testABindingNamingADeadKeyStillRunsTheColdSequence() async throws {
        StubURLProtocol.handler = { request in
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    AttestFixture.envelope(responseData: ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
                )
            case "/api/v2/device/taptopay/register":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    AttestFixture.envelope(responseData: ["deviceId": "dev_fresh"])
                )
            default:
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    AttestFixture.envelope(responseData: ["ok": true])
                )
            }
        }

        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev_stale", keyId: "dead_key", in: storage)
        let (sut, attestor, _) = AttestFixture.makeService(storage: storage)
        attestor.generateAssertionError = NSError(
            domain: AppAttestService.deviceCheckErrorDomain,
            code: 2,
            userInfo: nil
        )

        let result = try await sut.attest(entry: "myEntry", appId: "TEAM.bundle.id")

        XCTAssertEqual(result.deviceId, "dev_fresh", "a binding naming a key this device lost was answered from")
        XCTAssertEqual(attestor.generateKeyCalls, 1)
    }

    /// Two services over different stores are two devices, whatever entry point they
    /// name. They queue behind each other, and each then decides from its own store,
    /// so neither is handed a handle it cannot produce an assertion for.
    func testTwoServicesOverDifferentStoresEachGetTheirOwnDevice() async throws {
        let deviceIds = PathsBox()
        StubURLProtocol.handler = { request in
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    AttestFixture.envelope(responseData: ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
                )
            case "/api/v2/device/taptopay/register":
                let issued = "dev_\(UUID().uuidString)"
                deviceIds.append(issued)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    AttestFixture.envelope(responseData: ["deviceId": issued])
                )
            default:
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    AttestFixture.envelope(responseData: ["ok": true])
                )
            }
        }

        // Separate stores, as a caller building the service directly with its own
        // storage has. The entry point is the same, which is all the queue keys on.
        let firstStorage = InMemorySecureStorage()
        let secondStorage = InMemorySecureStorage()
        let (first, _, _) = AttestFixture.makeService(storage: firstStorage)
        let (second, _, _) = AttestFixture.makeService(storage: secondStorage)

        async let a = first.attest(entry: "myEntry", appId: "TEAM.bundle.id")
        async let b = second.attest(entry: "myEntry", appId: "TEAM.bundle.id")
        let results = try await [a, b]

        XCTAssertEqual(deviceIds.values.count, 2, "one service was handed the other's device")
        XCTAssertNotEqual(results[0].deviceId, results[1].deviceId)

        // What each was told matches what it can actually assert for.
        XCTAssertEqual(try first.binding(for: "myEntry")?.deviceId, results[0].deviceId)
        XCTAssertEqual(try second.binding(for: "myEntry")?.deviceId, results[1].deviceId)
    }

    /// Different entry points are what the bindings exist for, so they never wait
    /// for each other.
    func testTwoEntryPointsAttestWithoutWaitingForEachOther() async throws {
        StubURLProtocol.handler = { request in
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    AttestFixture.envelope(responseData: ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
                )
            case "/api/v2/device/taptopay/register":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    AttestFixture.envelope(responseData: ["deviceId": "dev_\(UUID().uuidString)"])
                )
            default:
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    AttestFixture.envelope(responseData: ["ok": true])
                )
            }
        }

        let storage = InMemorySecureStorage()
        let (sut, attestor, _) = AttestFixture.makeService(storage: storage)

        async let a = sut.attest(entry: "entryA", appId: "TEAM.bundle.id")
        async let b = sut.attest(entry: "entryB", appId: "TEAM.bundle.id")
        let results = try await [a, b]

        XCTAssertNotEqual(results[0].deviceId, results[1].deviceId)
        XCTAssertEqual(attestor.generateKeyCalls, 2, "one entry point took the other's attestation")
        XCTAssertEqual(try sut.allBindings().bindings.count, 2)
    }
}
