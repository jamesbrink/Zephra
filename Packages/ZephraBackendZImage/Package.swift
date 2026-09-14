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
        .package(url: "https://github.com/ml-explore/mlx-swift", revision: "ea8a179690170ca891a97bc0473198ab1ecda5f4"),
        // The streaming suites build a tiny model and load it through the kit's own weight
        // apply, which logs. ZImageKit pins the same package, so the graph is unchanged.
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
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
                // `ShardIndex` and `LayerWeightStreamError`, for the streaming suites.
                // ZImageKit has no test target by policy, so they live here.
                .product(name: "ZephraMLX", package: "ZephraMLXKit"),
                .product(name: "ZImage", package: "ZImageKit"),
                // Only to build the handful of small arrays the quantizer tests feed in.
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
    ]
)
