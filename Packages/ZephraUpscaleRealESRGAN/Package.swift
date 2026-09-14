// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZephraUpscaleRealESRGAN",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZephraUpscaleRealESRGAN", targets: ["ZephraUpscaleRealESRGAN"])
    ],
    dependencies: [
        // The upscaler seam and its error type, and nothing else from the app's value layer.
        .package(path: "../ZephraKit"),
        // The tiler. An upscale allocates in proportion to the picture it is producing, which
        // is the problem an autoencoder's decode has, so it is the same answer.
        .package(path: "../ZephraMLXKit"),
        // Pinned to the version every other package pins, so the graph stays one copy of MLX.
        .package(url: "https://github.com/ml-explore/mlx-swift", revision: "ea8a179690170ca891a97bc0473198ab1ecda5f4"),
    ],
    targets: [
        .target(
            name: "ZephraUpscaleRealESRGAN",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "ZephraCore", package: "ZephraKit"),
                .product(name: "ZephraMLX", package: "ZephraMLXKit"),
            ],
            // 2.4 MB of float16 weights carried in the bundle rather than downloaded: it is
            // noise beside a model download, and it takes an availability state, a download,
            // and a failure mode out of the engine. Copied rather than processed, because a
            // safetensors file is not an asset the build system knows how to compile.
            resources: [.copy("Resources/Weights")]
        ),
        .testTarget(
            name: "ZephraUpscaleRealESRGANTests",
            dependencies: [
                "ZephraUpscaleRealESRGAN",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
