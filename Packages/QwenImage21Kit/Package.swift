// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QwenImage21Kit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "QwenImage21", targets: ["QwenImage21"])
    ],
    dependencies: [
        // Pinned to the revision every other package pins, so the graph stays one copy of MLX.
        .package(url: "https://github.com/ml-explore/mlx-swift", revision: "ea8a179690170ca891a97bc0473198ab1ecda5f4"),
        // MLX work that is not this model's: the tiled decode every family's autoencoder wants.
        .package(path: "../ZephraMLXKit"),
        // The tokenizer, pinned exactly the way mlx-swift is: every package pins one version.
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "0.1.24"),
        // SnapshotUnderTest, for the suites that read a real snapshot's files.
        .package(path: "../ZephraKit"),
    ],
    targets: [
        .target(
            name: "QwenImage21",
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
            name: "QwenImage21Tests",
            dependencies: [
                "QwenImage21",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "ZephraMLX", package: "ZephraMLXKit"),
                // For reading a safetensors header without the weights behind it, which is how
                // a coverage suite checks 14 GB of tensors in a second.
                .product(name: "ZephraQuantization", package: "ZephraMLXKit"),
                .product(name: "ZephraTestSupport", package: "ZephraKit"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
