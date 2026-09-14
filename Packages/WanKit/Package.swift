// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WanKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Wan", targets: ["Wan"])
    ],
    dependencies: [
        // Pinned to the version every other package pins, so the graph stays one copy of MLX.
        .package(url: "https://github.com/ml-explore/mlx-swift", revision: "ea8a179690170ca891a97bc0473198ab1ecda5f4"),
        // MLX work that is not this model's: the packed loader, the pixel packer, the stream.
        .package(path: "../ZephraMLXKit"),
        // Pinned exactly, as every package pins it: the UMT5 tokenizer is read through it and
        // `TokenizerTests` pins that reading against the reference's ids.
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "0.1.24"),
        // SnapshotUnderTest, for the suites that read a real snapshot's files.
        .package(path: "../ZephraKit"),
    ],
    targets: [
        .target(
            name: "Wan",
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
            name: "WanTests",
            dependencies: [
                "Wan",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "ZephraMLX", package: "ZephraMLXKit"),
                // For reading a safetensors header without the weights behind it.
                .product(name: "ZephraQuantization", package: "ZephraMLXKit"),
                .product(name: "ZephraTestSupport", package: "ZephraKit"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
