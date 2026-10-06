@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
@testable import PayabliSDKTapToPay
import XCTest

@MainActor
final class OneSessionAcrossCapabilitiesTests: XCTestCase {
    override func tearDown() {
        PayabliSession.resetForTesting()
        super.tearDown()
    }

    func testBothCapabilitiesHoldOneCredentialHolder() async throws {
        let calls = ProviderCalls()
        let (payIn, ttp) = try await makeBothFacades(tokenProvider: {
            await calls.increment()
            return "tok"
        })

        let payInAuth = try XCTUnwrap(payIn.session?.auth)
        let ttpAuth = ttp.session.auth
        XCTAssertTrue(payInAuth === ttpAuth, "each capability holds its own credential holder")

        async let fromPayIn = payInAuth.currentAccessToken()
        async let fromTTP = ttpAuth.currentAccessToken()
        _ = try await (fromPayIn, fromTTP)
        let spent = await calls.count
        XCTAssertEqual(spent, 1, "concurrent cold reads across both capabilities spent \(spent) provider calls")
    }

    private func makeBothFacades(
        tokenProvider: @escaping PayabliTokenRefresh
    ) async throws -> (PayabliPayIn, PayabliTTP) {
        let session = try await PayabliSession.initialize(config: PayabliConfig(
            entryPoint: "demo",
            environment: .sandbox,
            tokenProvider: tokenProvider
        ))
        let payIn = PayabliPayIn(session: session)
        let ttp = try PayabliTTP(appId: "TEAM.app")
        return (payIn, ttp)
    }
}

private actor ProviderCalls {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
