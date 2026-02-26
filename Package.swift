// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WalkingPadSDK",
    platforms: [.macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "WalkingPadSDK", targets: ["WalkingPadSDK"]),
    ],
    targets: [
        .target(name: "WalkingPadSDK"),
        .testTarget(name: "WalkingPadSDKTests", dependencies: ["WalkingPadSDK"]),
    ]
)
