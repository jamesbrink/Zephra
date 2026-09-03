// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZephraBackendFlux2",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZephraBackendFlux2", targets: ["ZephraBackendFlux2"])
    ],
    dependencies: [
        .package(path: "../ZephraKit"),
        .package(path: "../ZephraMLXKit"),
        .package(path: "../Flux2Kit"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.3"),
    ],
    targets: [
        .target(
            name: "ZephraBackendFlux2",
            dependencies: [
                .product(name: "ZephraCore", package: "ZephraKit"),
                .product(name: "ZephraSnapshot", package: "ZephraKit"),
                .product(name: "ZephraMLX", package: "ZephraMLXKit"),
                .product(name: "ZephraQuantization", package: "ZephraMLXKit"),
                .product(name: "Flux2", package: "Flux2Kit"),
                .product(name: "MLX", package: "mlx-swift"),
            ]
        ),
        .testTarget(
            name: "ZephraBackendFlux2Tests",
            dependencies: [
                "ZephraBackendFlux2",
                .product(name: "ZephraCore", package: "ZephraKit"),
                .product(name: "ZephraTestSupport", package: "ZephraKit"),
                .product(name: "ZephraQuantization", package: "ZephraMLXKit"),
            ]
        ),
    ]
)
