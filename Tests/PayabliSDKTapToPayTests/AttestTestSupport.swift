@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// What more than one attestation suite needs to stand a service up.
///
/// Internal rather than shipped in `PayabliSDKTestUtils`: that module is a product
/// an integrator can link, so it imports the SDK plainly and sees only `public`.
/// Everything here reaches internal API — the designated initializer that takes the
/// providers, and `AttestedDevice` — so it can only live in a target that imports
/// the SDK with `@testable`.
enum AttestFixture {
    /// A service whose network is stubbed and whose platform values are fixed.
    static func makeService(
        storage: SecureStorage = InMemorySecureStorage(),
        hardwareIdProvider: @Sendable @escaping () throws -> String = { "fixed-hw-id" }
    ) throws -> (AppAttestService, MockAppAttestor, PayabliAuth) {
        let urlSession = StubURLProtocol.makeSession()
        let config = try PayabliConfig(
            accessToken: "seed",
            entryPoint: "myEntry",
            environment: .sandbox
        )
        // The holder comes first: the service's chain reads the token from it, so the same instance
        // has to serve the chain and the recovery layer above it.
        let auth = PayabliAuth(config: config)
        let service = PayabliService(
            environment: .sandbox,
            readToken: { await auth.currentAccessToken() },
            session: urlSession
        )
        let transport = AuthenticatedTransport(base: service, auth: auth)
        let attestor = MockAppAttestor()
        let sut = AppAttestService(
            transport: transport,
            attestor: attestor,
            storage: storage,
            hardwareIdProvider: hardwareIdProvider,
            modelProvider: { "iPhone15,2" },
            osVersionProvider: { "17.0" }
        )
        return (sut, attestor, auth)
    }

    /// The envelope every attestation endpoint answers in.
    static func envelope(responseData: [String: Any]) -> Data {
        let payload: [String: Any] = [
            "responseCode": 1,
            "isSuccess": true,
            "responseText": "OK",
            "responseData": responseData
        ]
        // The fixture's own input, so a throw here is a broken test rather than a
        // condition worth carrying.
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    static func ok(_ request: URLRequest, _ responseData: [String: Any]) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
            envelope(responseData: responseData)
        )
    }

    /// Writes a binding the way the service does, so a test starts warm.
    static func seedBinding(
        entry: String,
        deviceId: String,
        keyId: String,
        in storage: SecureStorage
    ) throws {
        let bindings = DeviceBindings([AttestedDevice(entry: entry, deviceId: deviceId, keyId: keyId)])
        let data = try JSONEncoder().encode(bindings)
        try storage.set(XCTUnwrap(String(bytes: data, encoding: .utf8)), forKey: PayabliKeychainKey.deviceBindings)
    }
}

/// Thread-safe box for the request bodies a stub handler saw.
final class BodyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Data?] = []

    var values: [Data?] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Data?) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(value)
    }
}

extension URLRequest {
    /// The body as a `URLProtocol` subclass actually receives it.
    ///
    /// `httpBody` is nil by the time a request reaches a protocol handler whenever
    /// the loader turned it into a stream, which it does for the bodies here. A test
    /// reading `httpBody` alone finds nothing and asserts nothing while looking like
    /// it checked the wire.
    var payabliTestBody: Data? {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}

/// What a Keychain keeps when the install that wrote it is gone.
///
/// Held separately from the store so a test can build a second store over it, which
/// is what a reinstall is: the app's own objects are new, the Keychain is not.
final class DurableBacking: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]

    func value(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return items[key]
    }

    func set(_ value: String, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        items[key] = value
    }

    func remove(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        items.removeValue(forKey: key)
    }
}

/// A store holding nothing of its own, so building a new one models an install
/// that reads a Keychain it did not write.
struct KeychainStandIn: SecureStorage {
    let backing: DurableBacking

    func string(forKey key: String) throws -> String? {
        backing.value(forKey: key)
    }

    func set(_ value: String, forKey key: String) throws {
        backing.set(value, forKey: key)
    }

    func remove(forKey key: String) throws {
        backing.remove(forKey: key)
    }
}

/// Thread-safe box so a stub handler can record what it saw, in order.
final class PathsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(value)
    }
}
