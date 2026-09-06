// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LTX2Kit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LTX2", targets: ["LTX2"])
    ],
    dependencies: [
        // Pinned to the version every other package pins, so the graph stays one copy of MLX.
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.3"),
        // MLX work that is not this model's: the packed loader, the pixel packer, the stream.
        .package(path: "../ZephraMLXKit"),
        // SnapshotUnderTest, for the suites that read a real snapshot's files.
        .package(path: "../ZephraKit"),
    ],
    targets: [
        .target(
            name: "LTX2",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "ZephraMLX", package: "ZephraMLXKit"),
            ]
        ),
        .testTarget(
            name: "LTX2Tests",
            dependencies: [
                "LTX2",
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
