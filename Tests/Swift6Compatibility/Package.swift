// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CocoaMQTTSwift6CompatibilityCheck",
    platforms: [
        .macOS(.v10_13)
    ],
    dependencies: [
        .package(name: "CocoaMQTT", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "Swift6Compatibility",
            dependencies: [
                .product(name: "CocoaMQTT", package: "CocoaMQTT"),
                .product(name: "CocoaMQTTWebSocket", package: "CocoaMQTT")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
