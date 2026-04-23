// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PayabliSDK",
    defaultLocalization: "en",
    platforms: [
        // 16.7 is the minimum required by FiservTTP / Apple's ProximityReader.
        // Non-TTP modules still compile for macOS for local `swift test`.
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
    // PayabliSDKCore and PayabliSDKTelemetry stay dep-free (NFR-8). PayabliSDKPayIn
    // pulls FiservTTP only on iOS via a platform-conditional product dependency so
    // macOS test compilation still works (the adapter file is gated with
    // `#if canImport(FiservTTP)`). Telemetry integrations with Sentry / PostHog
    // remain "bring your own instance".
    dependencies: [
        .package(url: "https://github.com/Fiserv/TTPPackage.git", from: "1.0.7")
    ],
    targets: [
        .target(
            name: "PayabliSDKCore",
            path: "Sources/PayabliSDKCore",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .target(
            name: "PayabliSDKPayIn",
            dependencies: [
                "PayabliSDKCore",
                .product(
                    name: "FiservTTP",
                    package: "TTPPackage",
                    condition: .when(platforms: [.iOS])
                )
            ],
            path: "Sources/PayabliSDKPayIn"
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
