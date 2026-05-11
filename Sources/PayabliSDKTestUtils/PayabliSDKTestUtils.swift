import Foundation

/// PayabliSDKTestUtils — a shipped collection of in-memory fixtures and
/// stubs (`StubURLProtocol`, `InMemorySecureStorage`, `MockAppAttestor`,
/// `MockTapToPayProvider`, `MockDeviceAttestationService`,
/// `InMemoryTelemetryTransport`) so host applications and future SDK
/// modules can write tests against the public PayabliSDK API without
/// re-implementing each stub.
///
/// Mirrors the pattern used by `apple/swift-nio`'s `NIOTestUtils` and
/// `apple/swift-log`'s `InMemoryLogging` libraries.
public enum PayabliSDKTestUtils {
    public static var version: String {
        Bundle(for: VersionMarker.self)
            .infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0.0.0"
    }

    private final class VersionMarker {}
}
