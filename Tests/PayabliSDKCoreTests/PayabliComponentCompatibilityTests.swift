import PayabliSDKCore
import XCTest

@MainActor
final class PayabliComponentCompatibilityTests: XCTestCase {
    func testNewConfigureRoutesToLegacyConfigureImplementation() throws {
        let component = LegacyConfigureComponent()
        let config = try testConfig(entryPoint: "legacy-entry")

        component.configure(config: config)

        XCTAssertEqual(component.configuredEntryPoint, "legacy-entry")
        XCTAssertEqual(component.configuredTheme?.primaryColorHex, PayabliTheme.default.primaryColorHex)
    }

    private func testConfig(entryPoint: String) throws -> PayabliConfig {
        try PayabliConfig(
            accessToken: "access-token",
            entryPoint: entryPoint,
            environment: .sandbox
        )
    }
}

@MainActor
private final class LegacyConfigureComponent: PayabliComponent {
    nonisolated static let componentId = "legacy"
    nonisolated static let sessionTier = PayabliSessionTier.tier1Transactional
    nonisolated static let requiredPermissions: [String] = []

    private(set) var configuredEntryPoint: String?
    private(set) var configuredTheme: PayabliTheme?

    func configure(config: PayabliConfig, theme: PayabliTheme) {
        configuredEntryPoint = config.entryPoint
        configuredTheme = theme
    }
}
