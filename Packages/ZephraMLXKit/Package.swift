// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZephraMLXKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZephraQuantization", targets: ["ZephraQuantization"])
    ],
    dependencies: [
        .package(path: "../ZephraKit"),
        // Pinned to the version ZImageKit and every backend package pin, so the graph
        // stays one copy of MLX.
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.3"),
    ],
    targets: [
        // Packing weights is the same job whatever produced them: read a safetensors shard,
        // decide a precision per tensor, pack, spill. Only the decision is family-specific,
        // and that arrives as a QuantizationPlan.
        .target(
            name: "ZephraQuantization",
            dependencies: [.product(name: "MLX", package: "mlx-swift")]
        ),
        .testTarget(
            name: "ZephraQuantizationTests",
            dependencies: [
                "ZephraQuantization",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "ZephraTestSupport", package: "ZephraKit"),
            ]
        ),
    ]
)
