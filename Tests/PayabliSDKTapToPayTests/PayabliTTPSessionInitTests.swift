import XCTest
@testable import PayabliSDKTapToPay
@testable import PayabliSDKCore

@MainActor
final class PayabliTTPSessionInitTests: XCTestCase {
    func testTwoFacadesShareTheSameAuth() async {
        let config = PayabliConfig(
            accessToken: "shared-token",
            entryPoint: "demo",
            environment: .sandbox
        )
        let session = PayabliSession(config: config)

        let ttp1 = PayabliTTP(
            session: session,
            appId: "T.app",
            provider: MockTapToPayProvider(),
            attestation: MockDeviceAttestationService()
        )
        let ttp2 = PayabliTTP(
            session: session,
            appId: "T.app",
            provider: MockTapToPayProvider(),
            attestation: MockDeviceAttestationService()
        )

        // Both facades hold the same actor reference.
        XCTAssertEqual(ObjectIdentifier(ttp1.auth), ObjectIdentifier(ttp2.auth))
    }
}
