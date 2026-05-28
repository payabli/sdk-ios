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
        // Dynamic per PRD NFR-11 — distributed as a dynamic XCFramework with
        // BUILD_LIBRARY_FOR_DISTRIBUTION=YES at binary-framework time.
        //
        // The umbrella `PayabliSDK` library aggregates every shippable target
        // so a host app can `import PayabliSDK*` modules à la carte after a
        // single `.product(name: "PayabliSDK", package: "PayabliSDK")` link.
        // The public Package.swift template under `.github/templates/` is the
        // source of truth for what consumers actually receive — it mirrors
        // the four shippable products below as `binaryTarget`s pointing at
        // signed XCFramework zips on Payabli's CDN.
        .library(
            name: "PayabliSDK",
            type: .dynamic,
            targets: ["PayabliSDKCore", "PayabliSDKTapToPay"]
        ),
        .library(
            name: "PayabliSDKCore",
            type: .dynamic,
            targets: ["PayabliSDKCore"]
        ),
        .library(
            name: "PayabliSDKTapToPay",
            type: .dynamic,
            targets: ["PayabliSDKTapToPay"]
        ),
        .library(
            name: "PayabliSDKTokenization",
            type: .dynamic,
            targets: ["PayabliSDKTokenization"]
        ),
        // `PayabliCardReaderCore` is exposed as a library product in the
        // private Package.swift so `xcodebuild -scheme PayabliCardReaderCore`
        // (driven by Scripts/build_release_frameworks.sh) can archive it
        // independently and produce its own XCFramework. Consumers of the
        // *public* Package.swift never see this as a stand-alone product —
        // the public template lists CardReaderCore only as a binaryTarget
        // pulled transitively by PayabliSDKTapToPay.
        .library(
            name: "PayabliCardReaderCore",
            type: .dynamic,
            targets: ["PayabliCardReaderCore"]
        ),
        .library(
            name: "PayabliSDKTelemetry",
            type: .dynamic,
            targets: ["PayabliSDKTelemetry"]
        ),
        .library(
            name: "PayabliSDKTestUtils",
            type: .dynamic,
            targets: ["PayabliSDKTestUtils"]
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
            name: "PayabliSDKTokenization",
            dependencies: ["PayabliSDKCore"],
            path: "Sources/PayabliSDKTokenization",
            exclude: [
                "README.md"
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
            name: "PayabliSDKTokenizationTests",
            dependencies: ["PayabliSDKCore", "PayabliSDKTokenization"],
            path: "Tests/PayabliSDKTokenizationTests"
        ),
        .testTarget(
            name: "PayabliSDKTestUtilsTests",
            dependencies: ["PayabliSDKTestUtils"],
            path: "Tests/PayabliSDKTestUtilsTests"
        )
    ]
)
