// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZephraBackendQwenImage",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZephraBackendQwenImage", targets: ["ZephraBackendQwenImage"])
    ],
    dependencies: [
        .package(path: "../ZephraKit"),
        .package(path: "../ZephraMLXKit"),
        .package(path: "../QwenImageKit"),
        .package(url: "https://github.com/ml-explore/mlx-swift", revision: "ea8a179690170ca891a97bc0473198ab1ecda5f4"),
    ],
    targets: [
        .target(
            name: "ZephraBackendQwenImage",
            dependencies: [
                .product(name: "ZephraCore", package: "ZephraKit"),
                .product(name: "ZephraSnapshot", package: "ZephraKit"),
                .product(name: "ZephraMLX", package: "ZephraMLXKit"),
                .product(name: "ZephraQuantization", package: "ZephraMLXKit"),
                .product(name: "QwenImage", package: "QwenImageKit"),
                .product(name: "MLX", package: "mlx-swift"),
            ]
        ),
        .testTarget(
            name: "ZephraBackendQwenImageTests",
            dependencies: [
                "ZephraBackendQwenImage",
                .product(name: "ZephraQuantization", package: "ZephraMLXKit"),
                .product(name: "ZephraTestSupport", package: "ZephraKit"),
            ]
        ),
    ]
)
