// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CocoaMQTTSwift6Consumer",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(name: "CocoaMQTT", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "Swift6Consumer",
            dependencies: [
                .product(name: "CocoaMQTT", package: "CocoaMQTT"),
                .product(name: "CocoaMQTTWebSocket", package: "CocoaMQTT")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
