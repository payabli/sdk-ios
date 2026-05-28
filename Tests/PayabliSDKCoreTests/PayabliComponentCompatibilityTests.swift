import PayabliSDKCore
import XCTest

@MainActor
final class PayabliComponentCompatibilityTests: XCTestCase {
    func testLegacyConfigureWithThemeRoutesToNewConfigure() {
        let component = NewConfigureComponent()
        let config = testConfig(entryPoint: "new-entry")

        component.configure(config: config, theme: .default)

        XCTAssertEqual(component.configuredEntryPoint, "new-entry")
    }

    func testNewConfigureRoutesToLegacyConfigureImplementation() {
        let component = LegacyConfigureComponent()
        let config = testConfig(entryPoint: "legacy-entry")

        component.configure(config: config)

        XCTAssertEqual(component.configuredEntryPoint, "legacy-entry")
        XCTAssertEqual(component.configuredTheme?.primaryColorHex, PayabliTheme.default.primaryColorHex)
    }

    private func testConfig(entryPoint: String) -> PayabliConfig {
        PayabliConfig(
            accessToken: "access-token",
            entryPoint: entryPoint,
            environment: .sandbox
        )
    }
}

@MainActor
private final class NewConfigureComponent: PayabliComponent {
    nonisolated static let componentId = "new"
    nonisolated static let sessionTier = PayabliSessionTier.tier1Transactional
    nonisolated static let requiredPermissions: [String] = []

    private(set) var configuredEntryPoint: String?

    func configure(config: PayabliConfig) {
        configuredEntryPoint = config.entryPoint
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
