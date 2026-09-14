// swift-tools-version: 6.0
// Vendored from https://github.com/mzbac/zimage.swift — see VENDORED.md.
import PackageDescription

let package = Package(
  name: "ZImageKit",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "ZImage", targets: ["ZImage"])
  ],
  dependencies: [
    // Pinned to the revision every other package pins, so the graph stays one copy of MLX.
    .package(url: "https://github.com/ml-explore/mlx-swift", revision: "ea8a179690170ca891a97bc0473198ab1ecda5f4"),
    .package(url: "https://github.com/huggingface/swift-transformers", exact: "0.1.24"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
    // The shared layer stream, so this family reads its blocks from disk the way every other
    // family does. A copy would not do: `LayerWeightStream` reports into `WeightStreamMeter`,
    // which the bench and `MLXRuntime.weightStreamReading()` read. See VENDORED.md.
    .package(path: "../ZephraMLXKit"),
  ],
  targets: [
    .target(
      name: "ZImage",
      dependencies: [
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXFast", package: "mlx-swift"),
        .product(name: "MLXNN", package: "mlx-swift"),
        .product(name: "MLXOptimizers", package: "mlx-swift"),
        .product(name: "MLXRandom", package: "mlx-swift"),
        .product(name: "Transformers", package: "swift-transformers"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "ZephraMLX", package: "ZephraMLXKit"),
      ],
      path: "Sources/ZImage",
      // Upstream is written for Swift 5; keep it compiling untouched.
      swiftSettings: [
        .swiftLanguageMode(.v5),
        // Async methods run on the caller's executor, so the engine's serial inference
        // executor keeps the MLX work instead of the cooperative pool.
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
      ]
    ),
  ]
)
