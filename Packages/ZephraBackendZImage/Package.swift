// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZephraBackendZImage",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZephraBackendZImage", targets: ["ZephraBackendZImage"])
    ],
    dependencies: [
        .package(path: "../ZephraKit"),
        .package(path: "../ZephraMLXKit"),
        .package(path: "../ZImageKit"),
        // For the runtime's cache and memory limits, the quantizer, and the microbench.
        // ZImageKit pins the same exact version, so this adds no new package to the graph.
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.3"),
    ],
    targets: [
        .target(
            name: "ZephraBackendZImage",
            dependencies: [
                .product(name: "ZephraCore", package: "ZephraKit"),
                .product(name: "ZephraSnapshot", package: "ZephraKit"),
                .product(name: "ZephraMLX", package: "ZephraMLXKit"),
                .product(name: "ZephraQuantization", package: "ZephraMLXKit"),
                .product(name: "ZImage", package: "ZImageKit"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
            ]
        ),
        // Covers the pure mapping layer only: nothing here loads weights or touches
        // the GPU. It still needs xcodebuild to build, because MLX links Metal.
        // Run it with `make test-backend`.
        .testTarget(
            name: "ZephraBackendZImageTests",
            dependencies: [
                "ZephraBackendZImage",
                .product(name: "ZephraCore", package: "ZephraKit"),
                .product(name: "ZephraSnapshot", package: "ZephraKit"),
                .product(name: "ZephraTestSupport", package: "ZephraKit"),
                .product(name: "ZephraQuantization", package: "ZephraMLXKit"),
                .product(name: "ZImage", package: "ZImageKit"),
                // Only to build the handful of small arrays the quantizer tests feed in.
                .product(name: "MLX", package: "mlx-swift"),
            ]
        ),
    ]
)
