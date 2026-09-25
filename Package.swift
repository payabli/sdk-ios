// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PayabliSDK",
    defaultLocalization: "en",
    platforms: [
        // iOS-only. 16.7 is the minimum required by PayabliCardReaderCore
        // (Apple's ProximityReader). The SDK is not intended to run on any
        // other Apple platform, so development, CI, and release all target
        // iPhone iOS (device + simulator) via `xcodebuild`. No macOS
        // compatibility shims are maintained.
        //
        // Non-Xcode IDEs (Cursor, VS Code with sourcekit-lsp) need to be
        // told that "host = iOS Simulator" — otherwise sourcekit-lsp falls
        // back to the macOS host triple and surfaces availability noise
        // (`ObservableObject` 10.15+, `URLSession.data(for:)` 12+, etc.)
        // even though build/CI/release are unaffected. See the repo-level
        // `.sourcekit-lsp/config.json` which configures that triple
        // automatically when you open the package in Cursor / VS Code.
        .iOS("16.7")
    ],
    products: [
        // Core and Telemetry are shared targets with no product of their own.
        // A product named like a target that two products contain stops SwiftPM
        // building that target once, and an app linking both products fails.
        //
        // An app links `PayabliSDK`, or `PayabliSDKTapToPay` and/or
        // `PayabliSDKPayInPaymentFlow`, never the umbrella with either: each
        // capability target is in the umbrella and has a product of its own.
        //
        // This manifest is what consumers resolve: a release tag is this file
        // at that commit. The zip of XCFrameworks attached to a GitHub Release
        // is for integrators who do not use SwiftPM.
        .library(
            name: "PayabliSDK",
            type: .dynamic,
            targets: [
                "PayabliSDKCore",
                "PayabliSDKTapToPay",
                "PayabliSDKPayInPaymentFlow",
                "PayabliSDKTelemetry"
            ]
        ),
        .library(
            name: "PayabliSDKTapToPay",
            type: .dynamic,
            targets: ["PayabliSDKTapToPay", "PayabliSDKTelemetry"]
        ),
        .library(
            name: "PayabliSDKPayInPaymentFlow",
            type: .dynamic,
            targets: ["PayabliSDKPayInPaymentFlow", "PayabliSDKTelemetry"]
        )
        // `PayabliSDKTestUtils` is a target and not a product. Its doubles conform to the
        // attestation, provider and storage protocols, so a linkable library of them requires
        // those protocols to be `public`.
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
            name: "PayabliSDKTapToPay",
            dependencies: [
                "PayabliSDKCore",
                .target(
                    name: "PayabliCardReaderCore",
                    condition: .when(platforms: [.iOS])
                )
            ],
            path: "Sources/PayabliSDKTapToPay",
            exclude: [
                "README.md",
                "Adapters/README.md"
            ]
        ),
        .target(
            name: "PayabliSDKTelemetry",
            dependencies: ["PayabliSDKCore"],
            path: "Sources/PayabliSDKTelemetry"
        ),
        .target(
            name: "PayabliSDKPayInPaymentFlow",
            dependencies: ["PayabliSDKCore"],
            path: "Sources/PayabliSDKPayInPaymentFlow",
            exclude: [
                "README.md",
                "LLM.md"
            ],
            resources: [
                .process("Resources/PayabliBrandAssets.xcassets")
            ]
        ),
        .target(
            name: "PayabliSDKTestUtils",
            dependencies: [
                "PayabliSDKCore",
                "PayabliSDKTapToPay"
            ],
            path: "Sources/PayabliSDKTestUtils"
        ),
        .testTarget(
            name: "PayabliSDKCoreTests",
            dependencies: ["PayabliSDKCore", "PayabliSDKTestUtils"],
            path: "Tests/PayabliSDKCoreTests"
        ),
        .testTarget(
            name: "PayabliSDKTapToPayTests",
            dependencies: ["PayabliSDKTapToPay", "PayabliSDKTestUtils"],
            path: "Tests/PayabliSDKTapToPayTests"
        ),
        .testTarget(
            name: "PayabliSDKTelemetryTests",
            dependencies: ["PayabliSDKTelemetry", "PayabliSDKTestUtils"],
            path: "Tests/PayabliSDKTelemetryTests"
        ),
        .testTarget(
            name: "PayabliSDKPayInPaymentFlowTests",
            dependencies: ["PayabliSDKCore", "PayabliSDKPayInPaymentFlow"],
            path: "Tests/PayabliSDKPayInPaymentFlowTests"
        ),
        .testTarget(
            name: "PayabliSDKTestUtilsTests",
            dependencies: ["PayabliSDKTestUtils"],
            path: "Tests/PayabliSDKTestUtilsTests"
        )
    ]
)
