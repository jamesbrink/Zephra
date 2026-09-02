// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZephraKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZephraCore", targets: ["ZephraCore"]),
        .library(name: "ZephraEngine", targets: ["ZephraEngine"]),
    ],
    targets: [
        .target(name: "ZephraCore"),
        .target(name: "ZephraEngine", dependencies: ["ZephraCore"]),
        .testTarget(name: "ZephraCoreTests", dependencies: ["ZephraCore"]),
    ]
)
