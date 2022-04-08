// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CocoaMQTT",
    // visionOS is supported through SwiftPM and compiled in CI. An explicit
    // declaration requires PackageDescription 5.9, while this manifest
    // intentionally remains compatible with Swift tools 5.7.
    platforms: [
        .macOS(.v10_13),
        .iOS(.v12),
        .tvOS(.v12)
    ],
    products: [
        .library(name: "CocoaMQTT", targets: ["CocoaMQTT"]),
        .library(name: "CocoaMQTTWebSocket", targets: ["CocoaMQTTWebSocket"])
    ],
    dependencies: [
        .package(url: "https://github.com/leeway1208/MqttCocoaAsyncSocket", from: "1.0.8"),
    ],
    targets: [
        .target(
            name: "CocoaMQTT",
            dependencies: ["MqttCocoaAsyncSocket"],
            path: "Source",
            exclude: ["Info.plist", "WebSocket"],
            resources: [.copy("PrivacyInfo.xcprivacy")],
            swiftSettings: [.define("IS_SWIFT_PACKAGE")]
        ),
        .target(
            name: "CocoaMQTTWebSocket",
            dependencies: ["CocoaMQTT"],
            path: "Source/WebSocket",
            swiftSettings: [.define("IS_SWIFT_PACKAGE")]
        ),
        .testTarget(
            name: "CocoaMQTTTests",
            dependencies: ["CocoaMQTT", "CocoaMQTTWebSocket"],
            path: "CocoaMQTTTests",
            exclude: ["Info.plist"],
            resources: [.copy("client-keycert.p12")],
            swiftSettings: [.define("IS_SWIFT_PACKAGE")]
        )
    ]
)
