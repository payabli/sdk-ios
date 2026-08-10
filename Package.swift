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
        // The umbrella `PayabliSDK` library aggregates the Core + Tap to Pay
        // targets on the critical path for primary SDK integrations.
        // PayInPaymentFlow and Telemetry are opt-in products that host apps
        // link explicitly when they need those surfaces.
        // The public Package.swift template under `.github/templates/` is the
        // source of truth for what consumers actually receive — it mirrors
        // the shippable products below as `binaryTarget`s pointing at
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
            name: "PayabliSDKPayInPaymentFlow",
            type: .dynamic,
            targets: ["PayabliSDKPayInPaymentFlow"]
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
        ),
        // Private, like `PayabliCardReaderCore` above: absent from the public
        // Package.swift template, so no consumer can link it and the
        // three-artifact split is unaffected.
        //
        // `Example/PayabliDemo` needs Core, card-present, and card-not-present in
        // one app. This is a constraint of `type: .dynamic` products built from
        // source, and nothing to do with the artifact split: linking two dynamic
        // products that both require the `PayabliSDKCore` *target* makes Xcode
        // try to hoist that target into its own dynamic library, which collides
        // with the same-named `PayabliSDKCore` *product*. One aggregate product
        // is one dylib, so there is nothing to hoist.
        //
        // Measured, so nobody re-runs these:
        //   - Dropping `type: .dynamic` from the three products makes the demo
        //     link all three individually with no aggregate at all. It is not an
        //     option, because `xcodebuild archive` then emits a bare
        //     `PayabliSDKCore.o` instead of `PayabliSDKCore.framework`, which is
        //     what `Scripts/build_release_frameworks.sh` packages. `.dynamic` is
        //     load-bearing for release; this product is the price of keeping it.
        //   - A shim package under `Example/` wrapping the three products
        //     reproduces the original error, so the aggregation has to sit in the
        //     package that owns the Core target.
        //   - Consumers never hit any of this. The public manifest ships
        //     `binaryTarget`s, which are prebuilt frameworks with no shared source
        //     target to hoist.
        //
        // Demo and QA hosts only. A real integrator links the individual
        // capability products, which is what keeps an app that never accepts
        // card-present from linking the card reader engine at all.
        .library(
            name: "PayabliSDKExampleAggregate",
            type: .dynamic,
            targets: [
                "PayabliSDKCore",
                "PayabliSDKTapToPay",
                "PayabliSDKPayInPaymentFlow"
            ]
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
