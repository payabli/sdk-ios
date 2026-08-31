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
        let (first, firstAttestor, _) = try AttestFixture.makeService(storage: storage)
        let (second, secondAttestor, _) = try AttestFixture.makeService(storage: storage)

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
        let (first, firstAttestor, _) = try AttestFixture.makeService(storage: storage)
        let (second, secondAttestor, _) = try AttestFixture.makeService(storage: storage)

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
        let (sut, attestor, _) = try AttestFixture.makeService(storage: storage)
        attestor.generateAssertionError = NSError(
            domain: AppAttestService.deviceCheckErrorDomain,
            code: 2,
            userInfo: nil
        )

        let result = try await sut.attest(entry: "myEntry", appId: "TEAM.bundle.id")

        XCTAssertEqual(result.deviceId, "dev_fresh", "a binding naming a key this device lost was answered from")
        XCTAssertEqual(attestor.generateKeyCalls, 1)
    }

    /// A caller cancelled while queued registers nothing when its turn arrives.
    /// A cancelled caller is released while the turn ahead is still running.
    ///
    /// Bounded, because the failure is a caller that never returns: without the
    /// bound this waits for the holder that the test itself is holding open, and
    /// reports a hang instead of the defect.
    func testACancelledCallerIsReleasedBeforeTheTurnAheadEnds() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path == "/api/v2/device/taptopay/register" {
                return AttestFixture.ok(request, ["deviceId": "dev_\(UUID().uuidString)"])
            }
            return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
        }

        let storage = InMemorySecureStorage()
        let (holder, holdingAttestor, _) = try AttestFixture.makeService(storage: storage)
        let (waiter, _, _) = try AttestFixture.makeService(storage: storage)

        let held = AsyncGate()
        let reached = AsyncGate()
        holdingAttestor.beforeGenerateKey = {
            reached.open()
            await held.wait()
        }

        async let holdersResult = holder.attest(entry: "myEntry", appId: "TEAM.bundle.id")
        await reached.wait()

        let released = expectation(description: "the cancelled caller returned")
        let queued = Task { try await waiter.attest(entry: "myEntry", appId: "TEAM.bundle.id") }
        Task {
            _ = try? await queued.value
            released.fulfill()
        }
        queued.cancel()

        // The holder is still held, so this can only complete if the cancellation
        // released the queued caller rather than leaving it behind the turn ahead.
        let outcome = await XCTWaiter().fulfillment(of: [released], timeout: 3)

        held.open()
        _ = try? await holdersResult

        XCTAssertEqual(
            outcome,
            .completed,
            "a cancelled caller stayed queued behind the attestation it was waiting for"
        )
    }

    func testACancelledCallerWaitingForATurnRegistersNothing() async throws {
        let paths = PathsBox()
        StubURLProtocol.handler = { request in
            paths.append(request.url!.path)
            if request.url!.path == "/api/v2/device/taptopay/register" {
                return AttestFixture.ok(request, ["deviceId": "dev_\(UUID().uuidString)"])
            }
            return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
        }

        let storage = InMemorySecureStorage()
        let (holder, holdingAttestor, _) = try AttestFixture.makeService(storage: storage)
        let (waiter, waitingAttestor, _) = try AttestFixture.makeService(storage: storage)

        let held = AsyncGate()
        let reached = AsyncGate()
        holdingAttestor.beforeGenerateKey = {
            reached.open()
            await held.wait()
        }

        async let holdersResult = holder.attest(entry: "myEntry", appId: "TEAM.bundle.id")
        await reached.wait()

        let queued = Task { try await waiter.attest(entry: "myEntry", appId: "TEAM.bundle.id") }
        queued.cancel()

        held.open()
        _ = try? await holdersResult

        // The caller's own outcome, not a count: work that ignored the cancellation
        // finishes after the counts are read, so counting is a race and this is not.
        do {
            _ = try await queued.value
            XCTFail("a cancelled caller was given an attestation")
        } catch is CancellationError {
            // What a cancelled caller gets.
        } catch {
            XCTFail("a cancelled caller got \(error) rather than a cancellation")
        }

        XCTAssertEqual(waitingAttestor.generateKeyCalls, 0, "a cancelled caller minted a key")
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
        let (first, _, _) = try AttestFixture.makeService(storage: firstStorage)
        let (second, _, _) = try AttestFixture.makeService(storage: secondStorage)

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
    /// One entry point held open, and the other has to get all the way through
    /// while it is held.
    ///
    /// Asserting the outcomes alone proves nothing here: a queue that serialized
    /// every entry point together would still end with two devices, two keys and
    /// two bindings. What separates the two is whether the second could finish
    /// before the first was let go, so the first is held inside its own attestation
    /// and the second is required to complete against a bound.
    func testAnEntryPointCompletesWhileAnotherIsHeldOpen() async throws {
        StubURLProtocol.handler = { request in
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            case "/api/v2/device/taptopay/register":
                return AttestFixture.ok(request, ["deviceId": "dev_\(UUID().uuidString)"])
            default:
                return AttestFixture.ok(request, ["ok": true])
            }
        }

        let storage = InMemorySecureStorage()
        let (holder, holdingAttestor, _) = try AttestFixture.makeService(storage: storage)
        let (other, otherAttestor, _) = try AttestFixture.makeService(storage: storage)

        let held = AsyncGate()
        let reached = AsyncGate()
        holdingAttestor.beforeGenerateKey = {
            reached.open()
            await held.wait()
        }

        async let holdersResult = holder.attest(entry: "entryA", appId: "TEAM.bundle.id")

        // Held for certain before the other one starts, so this is not a race the
        // test happens to win.
        await reached.wait()
        XCTAssertEqual(holdingAttestor.generateKeyCalls, 1)

        // An expectation rather than a racing task: a task group waits for its
        // children while a throw unwinds, and the child here is the caller queued
        // behind the held one, so the release that would free it can never run and
        // the failure never arrives. This records the failure, then the release
        // below drains both callers.
        let finished = expectation(description: "entryB completed while entryA was held")
        let othersAttestation = Task {
            let result = try await other.attest(entry: "entryB", appId: "TEAM.bundle.id")
            finished.fulfill()
            return result
        }
        await fulfillment(of: [finished], timeout: 5)

        held.open()
        let othersResult = try await othersAttestation.value
        XCTAssertEqual(otherAttestor.generateKeyCalls, 1)
        XCTAssertEqual(
            try other.binding(for: "entryB")?.deviceId,
            othersResult.deviceId,
            "entryB finished without a binding of its own"
        )

        let holders = try await holdersResult
        XCTAssertNotEqual(holders.deviceId, othersResult.deviceId)
        XCTAssertEqual(try holder.allBindings().bindings.count, 2)
    }
}

/// One-shot gate a test can hold work behind.
private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var opened = false

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow: Bool = lock.withLock {
                guard !opened else { return true }
                waiting.append(continuation)
                return false
            }
            if resumeNow {
                continuation.resume()
            }
        }
    }

    func open() {
        let held: [CheckedContinuation<Void, Never>] = lock.withLock {
            opened = true
            let held = waiting
            waiting = []
            return held
        }
        for continuation in held {
            continuation.resume()
        }
    }
}
