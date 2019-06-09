// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CocoaMQTT",
    products: [
        .library(
            name: "CocoaMQTT",
            targets: ["CocoaMQTT"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tbaranes/CocoaAsyncSocket", from: "7.7.0"),
    ],
    targets: [
        .target(name: "CocoaMQTT",
                dependencies: ["CocoaAsyncSocket"],
                path: "Source"),
        .testTarget(name: "CocoaMQTT-Tests", path: "CocoaMQTTTests"),
    ]
)
