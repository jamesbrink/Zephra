// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZephraMLXKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZephraQuantization", targets: ["ZephraQuantization"]),
        .library(name: "ZephraMLX", targets: ["ZephraMLX"]),
    ],
    dependencies: [
        .package(path: "../ZephraKit"),
        // Pinned to the version ZImageKit and every backend package pin, so the graph
        // stays one copy of MLX.
        .package(url: "https://github.com/ml-explore/mlx-swift", revision: "ea8a179690170ca891a97bc0473198ab1ecda5f4"),
    ],
    targets: [
        // Packing weights is the same job whatever produced them: read a safetensors shard,
        // decide a precision per tensor, pack, spill. Only the decision is family-specific,
        // and that arrives as a QuantizationPlan. ZephraCore and ZephraSnapshot are for the
        // one build every family runs the same way: a descriptor's plan into its `.partial`
        // directory, tallied for progress and stamped with its provenance.
        .target(
            name: "ZephraQuantization",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "ZephraCore", package: "ZephraKit"),
                .product(name: "ZephraSnapshot", package: "ZephraKit"),
            ]
        ),
        // MLX work that is the same job for every family and knows nothing about any of them:
        // the loader, the manifest reader, the rotary table, the pixel packer, the tiled decode,
        // the allocator's knobs and the streamed layer stack. A model package may depend on
        // this; nothing here may depend on a model package.
        .target(
            name: "ZephraMLX",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "ZephraCore", package: "ZephraKit"),
            ]
        ),
        .testTarget(
            name: "ZephraMLXTests",
            dependencies: [
                "ZephraMLX",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "ZephraCore", package: "ZephraKit"),
                .product(name: "ZephraTestSupport", package: "ZephraKit"),
            ]
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
