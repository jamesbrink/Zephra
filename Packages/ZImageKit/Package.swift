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
    .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.3"),
    .package(url: "https://github.com/huggingface/swift-transformers", exact: "0.1.24"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
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
