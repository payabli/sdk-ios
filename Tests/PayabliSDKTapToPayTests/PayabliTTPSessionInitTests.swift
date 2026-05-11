import XCTest
@testable import PayabliSDKTapToPay
@testable import PayabliSDKCore
import PayabliSDKTestUtils

@MainActor
final class PayabliTTPSessionInitTests: XCTestCase {
    func testTwoFacadesShareTheSameSession() async {
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

        // Both facades hold the same session reference.
        XCTAssertTrue(ttp1.session === ttp2.session)
    }
}
