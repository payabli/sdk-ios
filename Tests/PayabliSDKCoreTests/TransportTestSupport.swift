@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// The last four characters are what a sweep for a partial leak matches, so they are distinctive: the
/// tail of "test-token" is "oken", which is a substring of the messages the auth path writes.
let testToken = "test-token-QXJZ"

/// An auth holder for transport tests, which need a token source without being about auth.
///
/// No provider by default, so a 401 is terminal. Pass one when the refresh path is the subject.
func makeTestAuth(
    accessToken: String = testToken,
    tokenProvider: PayabliTokenRefresh? = nil,
    sink: RecordingLogSink? = nil
) throws -> PayabliAuth {
    let config = try PayabliConfig(
        accessToken: accessToken,
        tokenProvider: tokenProvider,
        entryPoint: "entry",
        environment: .sandbox
    )
    return PayabliAuth(
        config: config,
        logger: PayabliLogger(category: .auth, sink: sink ?? RecordingLogSink())
    )
}

/// Counts calls from any isolation, so a test can assert how many times a provider ran.
actor Counter {
    private(set) var count = 0

    func increment() -> Int {
        count += 1
        return count
    }
}

/// Records every request that reached the network and answers each one from the request itself.
///
/// The response is chosen from the request, not from its position, so a concurrent test carries no
/// assumption about arrival order: one caller can finish a whole refresh and replay before another has
/// sent anything.
final class RecordingStub: @unchecked Sendable {
    /// Status and body for one request.
    typealias Reply = (status: Int, body: Data)

    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let respond: @Sendable (URLRequest) -> Reply

    init(respond: @escaping @Sendable (URLRequest) -> Reply) {
        self.respond = respond
    }

    /// Answers every request alike.
    convenience init(status: Int = 200, body: Data = Data()) {
        self.init { _ in (status, body) }
    }

    func install() {
        StubURLProtocol.handler = { [self] request in
            lock.lock()
            recorded.append(request)
            lock.unlock()
            let reply = respond(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: reply.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, reply.body)
        }
    }

    func uninstall() {
        StubURLProtocol.handler = nil
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var count: Int {
        requests.count
    }

    /// The bearer each request carried, in order, with the scheme stripped.
    var sentTokens: [String?] {
        requests.map {
            $0.value(forHTTPHeaderField: "Authorization")?
                .replacingOccurrences(of: "Bearer ", with: "")
        }
    }
}

/// A service whose network is stubbed and whose chain reads from `auth`, and the recovery layer above
/// it. One holder serves both, which is what makes a replay carry the token a refresh minted.
func makeAuthenticatedStack(
    auth: PayabliAuth,
    sink: RecordingLogSink? = nil
) -> any PayabliTransport {
    let logger = PayabliLogger(category: .network, sink: sink ?? RecordingLogSink())
    let service = PayabliService.makeWithChain(
        environment: .sandbox,
        readToken: { await auth.currentAccessToken() },
        session: StubURLProtocol.makeSession(),
        logger: logger
    )
    return AuthenticatedTransport(base: service, auth: auth, logger: logger)
}

/// A service whose chain is the caller's, so a test can park a request at an exact point relative to
/// the bearer or assert what the chain did.
func makeStackWithChain(
    _ decorations: [any PayabliRequestDecoration],
    auth: PayabliAuth
) -> any PayabliTransport {
    let logger = PayabliLogger(category: .network, sink: RecordingLogSink())
    let service = PayabliService.makeWithDecorations(
        environment: .sandbox,
        decorations: decorations,
        session: StubURLProtocol.makeSession(),
        logger: logger
    )
    return AuthenticatedTransport(base: service, auth: auth, logger: logger)
}

/// Parks every request that reaches it until it is released, so a rotation lands at a chosen point in
/// the chain.
///
/// Its position in the chain is the point it parks: ahead of `BearerDecoration` it parks before the
/// token is read, behind it, after the token is stamped.
final class GateDecoration: PayabliRequestDecoration, @unchecked Sendable {
    private let lock = NSLock()
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var arrivals = 0
    private var released = false

    private var arrivalCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return arrivals
    }

    /// Resumes once `count` requests are parked, so a test acts on a state it established.
    ///
    /// Polled under a ceiling. A gate that is never reached means the chain did not run, and an
    /// unbounded wait on that hangs the whole suite, which prints no failure and reads like passing.
    func waitUntilParked(
        count: Int = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0 ..< 200 {
            if arrivalCount >= count {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        // Released before reporting, so nothing is left parked holding a task.
        release()
        XCTFail(
            "only \(arrivalCount) of \(count) requests reached the gate; the chain did not run",
            file: file,
            line: line
        )
    }

    func release() {
        lock.lock()
        released = true
        let waiting = parked
        parked = []
        lock.unlock()
        for continuation in waiting {
            continuation.resume()
        }
    }

    func decorate(_ request: PayabliRequest) async throws -> PayabliRequest {
        await withCheckedContinuation { continuation in
            lock.lock()
            if released {
                lock.unlock()
                continuation.resume()
                return
            }
            parked.append(continuation)
            arrivals += 1
            lock.unlock()
        }
        return request
    }
}

/// Records what the chain was asked to decorate, so a test can assert ordering and the request a later
/// step saw.
final class RecordingDecoration: PayabliRequestDecoration, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [PayabliRequest] = []
    private let stamp: [String: String]

    init(stamp: [String: String] = [:]) {
        self.stamp = stamp
    }

    var observed: [PayabliRequest] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }

    func decorate(_ request: PayabliRequest) async throws -> PayabliRequest {
        lock.lock()
        seen.append(request)
        lock.unlock()
        return stamp.isEmpty ? request : request.withHeaders(stamp)
    }
}

/// A one-slot thread-safe holder, for wiring a value into a closure that has to be built before it.
///
/// A provider that calls back into the SDK and the stack it calls are mutually dependent, so one of
/// the two exists first and the other arrives afterwards.
final class Slot<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?

    var value: Value? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ newValue: Value) {
        lock.lock()
        stored = newValue
        lock.unlock()
    }
}

/// Runs `work` under a ceiling and returns its outcome, or nil if it never finished.
///
/// The run is abandoned rather than awaited when the ceiling expires. Awaiting it instead would hang
/// the whole suite, and a hung suite prints no failure and reads exactly like a passing one, which is
/// why the case this exists for was skipped rather than left to run.
func outcomeWithinCeiling(_ work: @escaping @Sendable () async -> String) async -> String? {
    let slot = Slot<String>()
    Task { slot.set(await work()) }
    for _ in 0 ..< 200 {
        if let seen = slot.value {
            return seen
        }
        try? await Task.sleep(nanoseconds: 25_000_000)
    }
    return nil
}
