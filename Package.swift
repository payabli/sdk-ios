// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PayabliSDK",
    defaultLocalization: "en",
    platforms: [
        // iOS-only. 16.0 is what Core and PayIn need (`ContinuousClock`, `PresentationDetent`); Tap to Pay
        // needs 16.7 and carries `@available(iOS 16.7, *)`. Editors other than Xcode take the iOS triple
        // from `.sourcekit-lsp/config.json`.
        .iOS("16.0")
    ],
    products: [
        // Core and Telemetry are shared targets with no product of their own.
        // A product named like a target that two products contain stops SwiftPM
        // building that target once, and an app linking both products fails.
        //
        // An app links `PayabliSDK`, or `PayabliSDKTapToPay` and/or
        // `PayabliSDKPayIn`, never the umbrella with either: each
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
                "PayabliSDKPayIn",
                "PayabliSDKTelemetry"
            ]
        ),
        .library(
            name: "PayabliSDKTapToPay",
            type: .dynamic,
            targets: ["PayabliSDKTapToPay", "PayabliSDKTelemetry"]
        ),
        .library(
            name: "PayabliSDKPayIn",
            type: .dynamic,
            targets: ["PayabliSDKPayIn", "PayabliSDKTelemetry"]
        )
        // `PayabliSDKTestUtils` is a target and not a product. Its doubles conform to the
        // attestation, provider and storage protocols, so a linkable library of them requires
        // those protocols to be `public`.
    ],
    // Zero external dependencies: PayabliCardReaderCore is vendored under `ThirdParty/` and built as a
    // local target, so nothing about the shipped binary or this manifest names a third-party package.
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
            name: "PayabliSDKPayIn",
            dependencies: ["PayabliSDKCore"],
            path: "Sources/PayabliSDKPayIn",
            exclude: [
                "README.md",
                "LLM.md"
            ],
            resources: [
                .process("Resources/PayabliBrandAssets.xcassets"),
                .copy("Resources/PrivacyInfo.xcprivacy")
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
            name: "PayabliSDKPayInTests",
            dependencies: ["PayabliSDKCore", "PayabliSDKPayIn"],
            path: "Tests/PayabliSDKPayInTests"
        ),
        .testTarget(
            name: "PayabliSDKCrossCapabilityTests",
            dependencies: ["PayabliSDKCore", "PayabliSDKPayIn", "PayabliSDKTapToPay"],
            path: "Tests/PayabliSDKCrossCapabilityTests"
        ),
        .testTarget(
            name: "PayabliSDKTestUtilsTests",
            dependencies: ["PayabliSDKTestUtils"],
            path: "Tests/PayabliSDKTestUtilsTests"
        )
    ]
)
