// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZephraBackendQwenImage21",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZephraBackendQwenImage21", targets: ["ZephraBackendQwenImage21"])
    ],
    dependencies: [
        .package(path: "../ZephraKit"),
        .package(path: "../ZephraMLXKit"),
        .package(path: "../QwenImage21Kit"),
        // Pinned to the revision every other package pins, so the graph stays one copy of MLX.
        .package(
            url: "https://github.com/ml-explore/mlx-swift",
            revision: "ea8a179690170ca891a97bc0473198ab1ecda5f4"),
    ],
    targets: [
        .target(
            name: "ZephraBackendQwenImage21",
            dependencies: [
                .product(name: "ZephraCore", package: "ZephraKit"),
                .product(name: "ZephraSnapshot", package: "ZephraKit"),
                .product(name: "ZephraMLX", package: "ZephraMLXKit"),
                .product(name: "ZephraQuantization", package: "ZephraMLXKit"),
                .product(name: "QwenImage21", package: "QwenImage21Kit"),
                .product(name: "MLX", package: "mlx-swift"),
            ]
        ),
        .testTarget(
            name: "ZephraBackendQwenImage21Tests",
            dependencies: [
                "ZephraBackendQwenImage21",
                .product(name: "ZephraCore", package: "ZephraKit"),
                .product(name: "ZephraTestSupport", package: "ZephraKit"),
                .product(name: "ZephraQuantization", package: "ZephraMLXKit"),
                .product(name: "MLX", package: "mlx-swift"),
            ]
        ),
    ]
)
