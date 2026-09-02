// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QwenImageKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "QwenImage", targets: ["QwenImage"])
    ],
    dependencies: [
        // Pinned to the version every other package pins, so the graph stays one copy of MLX.
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.3"),
        // MLX work that is not this model's: the tiled decode every family's autoencoder wants.
        .package(path: "../ZephraMLXKit"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "0.1.24"),
    ],
    targets: [
        .target(
            name: "QwenImage",
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
            name: "QwenImageTests",
            dependencies: ["QwenImage", .product(name: "MLX", package: "mlx-swift")],
            resources: [.copy("Fixtures")]
        ),
    ]
)
