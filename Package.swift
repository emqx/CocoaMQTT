// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CocoaMQTT",
    platforms: [
        .macOS(.v10_13),
        .iOS(.v12),
        .tvOS(.v10)
    ],
    products: [
        .library(name: "CocoaMQTT", targets: [ "CocoaMQTT" ]),
        .library(name: "CocoaMQTTWebSocket", targets: [ "CocoaMQTTWebSocket" ])
    ],
    dependencies: [
        .package(url: "https://github.com/leeway1208/MqttCocoaAsyncSocket", from: "1.0.8"),
        .package(url: "https://github.com/daltoniam/Starscream.git", "4.0.8"..<"4.0.8"),
    ],
    targets: [
        .target(name: "CocoaMQTT",
                dependencies: [ "MqttCocoaAsyncSocket" ],
                path: "Source",
                exclude: ["CocoaMQTTWebSocket.swift"],
                resources: [.process("PrivacyInfo.xcprivacy")],
                swiftSettings: [ .define("IS_SWIFT_PACKAGE")]),
        .target(name: "CocoaMQTTWebSocket",
                dependencies: [ "CocoaMQTT", "Starscream" ],
                path: "Source",
                sources: ["CocoaMQTTWebSocket.swift"],
                swiftSettings: [ .define("IS_SWIFT_PACKAGE")]),
        .testTarget(name: "CocoaMQTTTests",
                    dependencies: [ "CocoaMQTT", "CocoaMQTTWebSocket" ],
                    path: "CocoaMQTTTests",
                    swiftSettings: [ .define("IS_SWIFT_PACKAGE")])
    ]
)
