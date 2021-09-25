// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CocoaMQTT",
    platforms: [
        .macOS(.v10_12),
        .iOS(.v10),
        .tvOS(.v10)
    ],
    products: [
        .library(name: "CocoaMQTT", targets: [ "CocoaMQTT" ]),
        .library(name: "CocoaMQTTWebSocket", targets: [ "CocoaMQTTWebSocket" ])
    ],
    dependencies: [
        .package(url: "https://github.com/robbiehanson/CocoaAsyncSocket", from: "7.6.4"),
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "3.1.1"),
    ],
    targets: [
        .target(name: "CocoaMQTT",
                dependencies: [ "CocoaAsyncSocket" ],
                path: "Source",
                exclude: ["CocoaMQTTWebSocket.swift"],
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
