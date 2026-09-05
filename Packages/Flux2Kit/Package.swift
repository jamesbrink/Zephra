// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flux2Kit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Flux2", targets: ["Flux2"])
    ],
    dependencies: [
        // Pinned to the version every other package pins, so the graph stays one copy of MLX.
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.3"),
        // MLX work that is not this model's: the tiled decode every family's autoencoder wants.
        .package(path: "../ZephraMLXKit"),
        // The tokenizer, pinned exactly the way mlx-swift is: every package pins one version.
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "0.1.24"),
        // SnapshotUnderTest, for the suites that read a real snapshot's files.
        .package(path: "../ZephraKit"),
    ],
    targets: [
        .target(
            name: "Flux2",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "Transformers", package: "swift-transformers"),
                .product(name: "ZephraMLX", package: "ZephraMLXKit"),
            ]
        ),
        .testTarget(
            name: "Flux2Tests",
            dependencies: [
                "Flux2",
                .product(name: "MLX", package: "mlx-swift"),
                // For reading a safetensors header without the weights behind it, which is how
                // the coverage test checks 8 GB of tensors in a second.
                .product(name: "ZephraQuantization", package: "ZephraMLXKit"),
                .product(name: "ZephraTestSupport", package: "ZephraKit"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
