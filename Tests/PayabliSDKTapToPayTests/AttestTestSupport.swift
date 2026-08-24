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
    ) -> (AppAttestService, MockAppAttestor, PayabliAuth) {
        let urlSession = StubURLProtocol.makeSession()
        let service = PayabliService(environment: .sandbox, session: urlSession)
        let config = PayabliConfig(
            accessToken: "seed",
            entryPoint: "myEntry",
            environment: .sandbox
        )
        let auth = PayabliAuth(config: config)
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
