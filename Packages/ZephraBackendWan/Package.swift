// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZephraBackendWan",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZephraBackendWan", targets: ["ZephraBackendWan"])
    ],
    dependencies: [
        .package(path: "../ZephraKit"),
        .package(path: "../ZephraMLXKit"),
        .package(path: "../WanKit"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.3"),
    ],
    targets: [
        .target(
            name: "ZephraBackendWan",
            dependencies: [
                .product(name: "ZephraCore", package: "ZephraKit"),
                .product(name: "ZephraSnapshot", package: "ZephraKit"),
                .product(name: "ZephraMedia", package: "ZephraKit"),
                .product(name: "ZephraMLX", package: "ZephraMLXKit"),
                .product(name: "ZephraQuantization", package: "ZephraMLXKit"),
                .product(name: "Wan", package: "WanKit"),
                .product(name: "MLX", package: "mlx-swift"),
            ]
        ),
        .testTarget(
            name: "ZephraBackendWanTests",
            dependencies: [
                "ZephraBackendWan",
                .product(name: "ZephraCore", package: "ZephraKit"),
                .product(name: "ZephraTestSupport", package: "ZephraKit"),
                .product(name: "ZephraQuantization", package: "ZephraMLXKit"),
                .product(name: "MLX", package: "mlx-swift"),
            ]
        ),
    ]
)
