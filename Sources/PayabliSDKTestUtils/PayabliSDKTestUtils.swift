import Foundation
import PayabliSDKCore

/// PayabliSDKTestUtils — in-memory fixtures and stubs (`StubURLProtocol`,
/// `InMemorySecureStorage`, `MockAppAttestor`, `MockTapToPayProvider`,
/// `MockDeviceAttestationService`, `InMemoryTelemetryTransport`) so this
/// package's own test targets can write tests without re-implementing each
/// stub.
///
/// A target rather than a product, and `package` throughout, so no consumer
/// can import the module.
package enum PayabliSDKTestUtils {
    package static var version: String {
        PayabliCore.version
    }
}
