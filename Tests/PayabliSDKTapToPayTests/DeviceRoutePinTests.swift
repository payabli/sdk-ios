@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// Device routes that pin their credential, over the wire: `/challenge`, `/register`, `/attest` and `/activate` each send
/// a refused token once and keep it for the session to renew. A 401 whose envelope declines under 401 is the device
/// refused, not the token.
final class DeviceRoutePinTests: XCTestCase {
    private static let challenge = "/api/v2/device/taptopay/challenge"
    private static let register = "/api/v2/device/taptopay/register"
    private static let attest = "/api/v2/device/taptopay/attest"
    private static let activate = "/api/v2/device/taptopay/activate"

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - Pinned routes

    func testA401OnChallengeIsSentOnceAndAsksTheProviderForNothing() async throws {
        let paths = PathsBox()
        StubURLProtocol.handler = Self.coldSequence(paths: paths, refusing: Self.challenge)
        let provider = Counter()
        let (sut, _, _) = try AttestFixture.makeService(tokenProvider: Self.rotating(provider))

        let failure = await failure { _ = try await sut.attest(entry: "myEntry") }

        XCTAssertTrue(failure is PinnedTokenRefusal, "got \(failure)")
        XCTAssertEqual(paths.values, [Self.challenge], "no replay, and nothing after it")
        let calls = await provider.count
        XCTAssertEqual(calls, 1, "the first token only: nothing was refreshed")
    }

    func testA401OnRegisterIsSentOnceAndAsksTheProviderForNothing() async throws {
        let paths = PathsBox()
        StubURLProtocol.handler = Self.coldSequence(paths: paths, refusing: Self.register)
        let provider = Counter()
        let (sut, _, _) = try AttestFixture.makeService(tokenProvider: Self.rotating(provider))

        let failure = await failure { _ = try await sut.attest(entry: "myEntry") }

        XCTAssertTrue(failure is PinnedTokenRefusal, "got \(failure)")
        XCTAssertEqual(paths.values, [Self.challenge, Self.register], "no replay, and nothing after it")
        let calls = await provider.count
        XCTAssertEqual(calls, 1, "the first token only: nothing was refreshed")
    }

    func testA401OnAttestIsSentOnceAndAsksTheProviderForNothing() async throws {
        let paths = PathsBox()
        StubURLProtocol.handler = Self.coldSequence(paths: paths, refusing: Self.attest)
        let provider = Counter()
        let (sut, _, _) = try AttestFixture.makeService(tokenProvider: Self.rotating(provider))

        let failure = await failure { _ = try await sut.attest(entry: "myEntry") }

        XCTAssertTrue(failure is PinnedTokenRefusal, "got \(failure)")
        XCTAssertEqual(paths.values.filter { $0 == Self.attest }.count, 1, "no replay")
        let calls = await provider.count
        XCTAssertEqual(calls, 1, "the first token only: nothing was refreshed")
    }

    func testA401OnActivateIsSentOnceAndAsksTheProviderForNothing() async throws {
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev_1", keyId: "key_1", in: storage)
        let paths = PathsBox()
        StubURLProtocol.handler = { request in
            paths.append(request.url!.path)
            if request.url!.path == Self.activate {
                return Self.status(401, request)
            }
            return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
        }
        let provider = Counter()
        let (sut, _, _) = try AttestFixture.makeService(storage: storage, tokenProvider: Self.rotating(provider))

        let failure = await failure {
            try await sut.activateDevice(activationCode: "123456", entry: "myEntry", activationId: "dev_1")
        }

        XCTAssertTrue(failure is PinnedTokenRefusal, "got \(failure)")
        XCTAssertEqual(paths.values.filter { $0 == Self.activate }.count, 1, "no replay")
        let calls = await provider.count
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try sut.binding(for: "myEntry")?.deviceId, "dev_1", "a refused token keeps the binding")
    }

    func testA401WhoseEnvelopeSays401OnEachColdRouteIsTheDeviceRefusedNotTheToken() async throws {
        for route in [Self.challenge, Self.register, Self.attest] {
            let paths = PathsBox()
            StubURLProtocol.handler = Self.coldSequence(paths: paths, refusing: route, body: Self.declining401)
            let provider = Counter()
            let (sut, _, _) = try AttestFixture.makeService(tokenProvider: Self.rotating(provider))

            let failure = await failure { _ = try await sut.attest(entry: "myEntry") }

            XCTAssertFalse(failure is PinnedTokenRefusal, "\(route): an envelope 401 was read as a refused token")
            XCTAssertEqual(
                (TapToPayErrorTranslation.hostError(for: failure) as? any PayabliError)?.code, 3005, "\(route): got \(failure)"
            )
            XCTAssertEqual(paths.values.filter { $0 == route }.count, 1, "\(route): no replay")
            let calls = await provider.count
            XCTAssertEqual(calls, 1, "\(route): the first token only: nothing was renewed")
        }
    }

    // MARK: - A binding the service no longer holds

    func testAnActivationRefusedBecauseTheBindingIsGoneDropsItAndAsksForSetupAgain() async throws {
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev_1", keyId: "key_1", in: storage)
        StubURLProtocol.handler = Self.refusingActivation(reason: BindingRefusal.text)
        let (sut, _, _) = try AttestFixture.makeService(storage: storage)

        let failure = await failure {
            try await sut.activateDevice(activationCode: "123456", entry: "myEntry", activationId: "dev_1")
        }

        XCTAssertEqual((TapToPayErrorTranslation.hostError(for: failure) as? any PayabliError)?.code, 3005, "got \(failure)")
        XCTAssertNil(try sut.binding(for: "myEntry"), "a binding the service no longer holds was kept")
    }

    func testAnActivation401WhoseEnvelopeSays401WithAnyOtherTextDropsTheBindingAndRenewsNothing() async throws {
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev_1", keyId: "key_1", in: storage)
        StubURLProtocol.handler = Self.refusingActivation(reason: "Unauthorized")
        let provider = Counter()
        let (sut, _, _) = try AttestFixture.makeService(storage: storage, tokenProvider: Self.rotating(provider))

        let failure = await failure {
            try await sut.activateDevice(activationCode: "123456", entry: "myEntry", activationId: "dev_1")
        }

        XCTAssertFalse(failure is PinnedTokenRefusal, "an envelope 401 was read as a refused token")
        XCTAssertEqual((TapToPayErrorTranslation.hostError(for: failure) as? any PayabliError)?.code, 3005, "got \(failure)")
        XCTAssertNil(try sut.binding(for: "myEntry"), "a binding the service refused was kept")
        let calls = await provider.count
        XCTAssertEqual(calls, 1, "the first token only: nothing was renewed")
    }

    func testAnActivation401WithTheRevocationTextButNoCodeIsARefusedToken() async throws {
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev_1", keyId: "key_1", in: storage)
        let body = #"{"isSuccess":false,"responseText":"Declined","responseData":{"resultText":"\#(BindingRefusal.text)"}}"#
        StubURLProtocol.handler = { request in
            if request.url!.path == Self.activate {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Data(body.utf8)
                )
            }
            return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
        }
        let (sut, _, _) = try AttestFixture.makeService(storage: storage)

        let failure = await failure {
            try await sut.activateDevice(activationCode: "123456", entry: "myEntry", activationId: "dev_1")
        }

        XCTAssertTrue(failure is PinnedTokenRefusal, "an envelope naming no code was read by its text: \(failure)")
        XCTAssertEqual(try sut.binding(for: "myEntry")?.deviceId, "dev_1")
    }

    func testAnActivationRefusalInTheBodyWithAnyOtherTextDropsTheBinding() async throws {
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev_1", keyId: "key_1", in: storage)
        let body = #"{"isSuccess":false,"responseText":"Declined","responseData":{"resultCode":401,"resultText":"Unauthorized"}}"#
        StubURLProtocol.handler = { request in
            if request.url!.path == Self.activate {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Data(body.utf8)
                )
            }
            return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
        }
        let (sut, _, _) = try AttestFixture.makeService(storage: storage)

        let failure = await failure {
            try await sut.activateDevice(activationCode: "123456", entry: "myEntry", activationId: "dev_1")
        }

        XCTAssertEqual((TapToPayErrorTranslation.hostError(for: failure) as? any PayabliError)?.code, 3005, "got \(failure)")
        XCTAssertNil(try sut.binding(for: "myEntry"), "a binding the service refused was kept")
    }

    func testAnActivationRefusalInTheBodyWithTheBindingGoneTextDropsIt() async throws {
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev_1", keyId: "key_1", in: storage)
        let body = #"{"isSuccess":false,"responseText":"Declined","responseData":{"resultCode":401,"resultText":"\#(BindingRefusal.text)"}}"#
        StubURLProtocol.handler = { request in
            if request.url!.path == Self.activate {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Data(body.utf8)
                )
            }
            return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
        }
        let (sut, _, _) = try AttestFixture.makeService(storage: storage)

        let failure = await failure {
            try await sut.activateDevice(activationCode: "123456", entry: "myEntry", activationId: "dev_1")
        }

        XCTAssertEqual((TapToPayErrorTranslation.hostError(for: failure) as? any PayabliError)?.code, 3005, "got \(failure)")
        XCTAssertNil(try sut.binding(for: "myEntry"))
    }

    // MARK: - Helpers

    /// `seed` first, then `renewed-2`, `renewed-3` and so on, counting every call.
    private static func rotating(_ calls: Counter) -> PayabliTokenRefresh {
        {
            let call = await calls.increment()
            return call == 1 ? "seed" : "renewed-\(call)"
        }
    }

    private static let declining401 = Data(
        #"{"isSuccess":false,"responseText":"Declined","responseData":{"resultCode":401,"resultText":"Unauthorized"}}"#.utf8
    )

    /// The cold sequence, with `refused` answering 401 to every token, carrying `body`.
    private static func coldSequence(paths: PathsBox, refusing refused: String, body: Data = Data()) -> StubURLProtocol.Handler {
        { request in
            let path = request.url!.path
            paths.append(path)
            if path == refused {
                return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!, body)
            }
            switch path {
            case challenge:
                return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            case register:
                return AttestFixture.ok(request, ["deviceId": "dev_1"])
            default:
                return AttestFixture.ok(request, ["ok": true])
            }
        }
    }

    private static func refusingActivation(reason: String) -> StubURLProtocol.Handler {
        let body = #"{"isSuccess":false,"responseText":"Declined","responseData":{"resultCode":401,"resultText":"\#(reason)"}}"#
        return { request in
            if request.url!.path == activate {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Data(body.utf8)
                )
            }
            return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
        }
    }

    private static func status(_ code: Int, _ request: URLRequest) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!, Data())
    }

    /// What `block` threw. A success fails the test here, so the assertions after it are never quietly skipped.
    private func failure(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ block: () async throws -> Void
    ) async -> any Error {
        do {
            try await block()
            XCTFail("expected a failure, got a success", file: file, line: line)
            return CancellationError()
        } catch {
            return error
        }
    }
}

/// Counts calls from any isolation, so a test can assert how many times a provider ran.
private actor Counter {
    private(set) var count = 0

    func increment() -> Int {
        count += 1
        return count
    }
}
