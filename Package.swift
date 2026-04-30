// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PayabliSDK",
    defaultLocalization: "en",
    platforms: [
        // 16.7 is the minimum required by PayabliCardReaderCore (Apple's
        // ProximityReader). Non-TTP modules still compile for macOS so local
        // `swift test` runs without requiring a simulator.
        .iOS("16.7"),
        .macOS(.v12)
    ],
    products: [
        // Dynamic per PRD NFR-11 — distributed as a dynamic XCFramework with
        // BUILD_LIBRARY_FOR_DISTRIBUTION=YES at binary-framework time.
        .library(
            name: "PayabliSDK",
            type: .dynamic,
            targets: ["PayabliSDKCore", "PayabliSDKPayIn"]
        ),
        .library(
            name: "PayabliSDKCore",
            type: .dynamic,
            targets: ["PayabliSDKCore"]
        ),
        .library(
            name: "PayabliSDKPayIn",
            type: .dynamic,
            targets: ["PayabliSDKPayIn"]
        ),
        .library(
            name: "PayabliSDKTelemetry",
            type: .dynamic,
            targets: ["PayabliSDKTelemetry"]
        )
    ],
    // Zero external SPM dependencies. PayabliCardReaderCore (MIT-licensed Tap
    // to Phone engine) is vendored at `ThirdParty/PayabliCardReaderCoreSource/`
    // and compiled as a local target so the public Package.swift, Package.resolved,
    // `otool -L`, and `.swiftinterface` of the shipped binary contain no
    // third-party package references. Telemetry integrations with Sentry /
    // PostHog remain "bring your own instance".
    dependencies: [],
    targets: [
        .target(
            name: "PayabliSDKCore",
            path: "Sources/PayabliSDKCore",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .target(
            name: "PayabliCardReaderCore",
            path: "ThirdParty/PayabliCardReaderCoreSource/Sources/PayabliCardReaderCore",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .target(
            name: "PayabliSDKPayIn",
            dependencies: [
                "PayabliSDKCore",
                .target(
                    name: "PayabliCardReaderCore",
                    condition: .when(platforms: [.iOS])
                )
            ],
            path: "Sources/PayabliSDKPayIn",
            exclude: [
                "TapToPay/README.md",
                "TapToPay/Adapters/README.md",
                "Resources/README.md"
            ],
            resources: [
                .process("Resources/PayabliBrandAssets.xcassets"),
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .target(
            name: "PayabliSDKTelemetry",
            dependencies: ["PayabliSDKCore"],
            path: "Sources/PayabliSDKTelemetry"
        ),
        .testTarget(
            name: "PayabliSDKCoreTests",
            dependencies: ["PayabliSDKCore"],
            path: "Tests/PayabliSDKCoreTests"
        ),
        .testTarget(
            name: "PayabliSDKPayInTests",
            dependencies: ["PayabliSDKPayIn"],
            path: "Tests/PayabliSDKPayInTests"
        ),
        .testTarget(
            name: "PayabliSDKTelemetryTests",
            dependencies: ["PayabliSDKTelemetry"],
            path: "Tests/PayabliSDKTelemetryTests"
        ),
        .testTarget(
            name: "PayabliSDKIntegrationTests",
            dependencies: ["PayabliSDKCore", "PayabliSDKPayIn"],
            path: "Tests/PayabliSDKIntegrationTests"
        )
    ]
)
