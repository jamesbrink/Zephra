// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZephraBackendLTX2",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZephraBackendLTX2", targets: ["ZephraBackendLTX2"])
    ],
    dependencies: [
        .package(path: "../ZephraKit"),
        .package(path: "../ZephraMLXKit"),
        .package(path: "../LTX2Kit"),
        .package(url: "https://github.com/ml-explore/mlx-swift", revision: "ea8a179690170ca891a97bc0473198ab1ecda5f4"),
    ],
    targets: [
        .target(
            name: "ZephraBackendLTX2",
            dependencies: [
                .product(name: "ZephraCore", package: "ZephraKit"),
                .product(name: "ZephraSnapshot", package: "ZephraKit"),
                .product(name: "ZephraMedia", package: "ZephraKit"),
                .product(name: "ZephraMLX", package: "ZephraMLXKit"),
                .product(name: "ZephraQuantization", package: "ZephraMLXKit"),
                .product(name: "LTX2", package: "LTX2Kit"),
                .product(name: "MLX", package: "mlx-swift"),
            ]
        ),
        .testTarget(
            name: "ZephraBackendLTX2Tests",
            dependencies: [
                "ZephraBackendLTX2",
                .product(name: "ZephraCore", package: "ZephraKit"),
                .product(name: "ZephraTestSupport", package: "ZephraKit"),
                .product(name: "ZephraQuantization", package: "ZephraMLXKit"),
                .product(name: "MLX", package: "mlx-swift"),
            ]
        ),
    ]
)
