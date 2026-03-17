// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PayabliTTP",
    platforms: [
        .iOS("16.7")
    ],
    products: [
        .library(
            name: "PayabliTTP",
            targets: ["PayabliTTP"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Fiserv/TTPPackage.git", from: "1.0.7")
    ],
    targets: [
        .target(
            name: "PayabliTTP",
            dependencies: [
                .product(name: "FiservTTP", package: "TTPPackage")
            ],
            path: "Sources/PayabliTTP"
        ),
        .testTarget(
            name: "PayabliTTPTests",
            dependencies: ["PayabliTTP"],
            path: "Tests/PayabliTTPTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
