@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// Which device routes pin their credential, over the wire: `/attest` and `/activate` send a refused token once and
/// keep it for the session to renew, while `/challenge` and `/register`, which run before a binding exists, recover as
/// any route does. A binding the service no longer holds is told apart from a refused token by its text.
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

    func testA401OnAttestIsSentOnceAndAsksTheProviderForNothing() async throws {
        let paths = PathsBox()
        StubURLProtocol.handler = Self.coldSequence(paths: paths, refusing: Self.attest, unless: nil)
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

    // MARK: - Routes that recover

    func testA401OnChallengeIsStillRefreshedAndReplayed() async throws {
        let paths = PathsBox()
        StubURLProtocol.handler = Self.coldSequence(paths: paths, refusing: Self.challenge, unless: "renewed-2")
        let provider = Counter()
        let (sut, _, _) = try AttestFixture.makeService(tokenProvider: Self.rotating(provider))

        let result = try await sut.attest(entry: "myEntry")

        XCTAssertEqual(result.deviceId, "dev_1")
        XCTAssertEqual(paths.values, [Self.challenge, Self.challenge, Self.register, Self.attest])
    }

    func testA401OnRegisterIsStillRefreshedAndReplayed() async throws {
        let paths = PathsBox()
        StubURLProtocol.handler = Self.coldSequence(paths: paths, refusing: Self.register, unless: "renewed-2")
        let provider = Counter()
        let (sut, _, _) = try AttestFixture.makeService(tokenProvider: Self.rotating(provider))

        let result = try await sut.attest(entry: "myEntry")

        XCTAssertEqual(result.deviceId, "dev_1")
        XCTAssertEqual(paths.values, [Self.challenge, Self.register, Self.register, Self.attest])
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

    func testAnActivation401WithAnyOtherTextIsARefusedToken() async throws {
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev_1", keyId: "key_1", in: storage)
        // The text the service sends, with a final period it does not send.
        StubURLProtocol.handler = Self.refusingActivation(reason: BindingRefusal.text + ".")
        let (sut, _, _) = try AttestFixture.makeService(storage: storage)

        let failure = await failure {
            try await sut.activateDevice(activationCode: "123456", entry: "myEntry", activationId: "dev_1")
        }

        XCTAssertTrue(failure is PinnedTokenRefusal, "got \(failure)")
        XCTAssertEqual(try sut.binding(for: "myEntry")?.deviceId, "dev_1")
    }

    // MARK: - Helpers

    /// `seed` first, then `renewed-2`, `renewed-3` and so on, counting every call.
    private static func rotating(_ calls: Counter) -> PayabliTokenRefresh {
        {
            let call = await calls.increment()
            return call == 1 ? "seed" : "renewed-\(call)"
        }
    }

    /// The cold sequence, with `refused` answering 401 to every token but `accepted`.
    private static func coldSequence(
        paths: PathsBox,
        refusing refused: String,
        unless accepted: String?
    ) -> StubURLProtocol.Handler {
        { request in
            let path = request.url!.path
            paths.append(path)
            if path == refused, bearer(of: request) != accepted {
                return status(401, request)
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

    private static func bearer(of request: URLRequest) -> String? {
        request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "")
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
