// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "CocoaMQTT",
    products: [
        .library(name: "CocoaMQTT", targets: ["CocoaMQTT"]),
        ],
    dependencies: [
        .package(url: "https://github.com/robbiehanson/CocoaAsyncSocket", from: "7.6.4"),
        .package(url: "https://github.com/daltoniam/Starscream.git", .upToNextMajor(from: "3.0.0"))
    ],
    targets: [
        .target(
            name: "CocoaMQTT",
            dependencies: ["CocoaAsyncSocket", "Starscream"],
            path: "Source"
        ),
        .testTarget(
            name: "CocoaMQTTTests",
            dependencies: ["CocoaMQTT"],
            path: "CocoaMQTTTests"
        ),
    ]
)
