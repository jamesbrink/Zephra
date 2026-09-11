// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZephraKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZephraCore", targets: ["ZephraCore"]),
        .library(name: "ZephraSnapshot", targets: ["ZephraSnapshot"]),
        .library(name: "ZephraEngine", targets: ["ZephraEngine"]),
        // Frames in, an MP4 out. Foundation and AVFoundation, no MLX, so a video backend and
        // the app share one writer and `make test` covers it.
        .library(name: "ZephraMedia", targets: ["ZephraMedia"]),
        // Test fixtures shared by this package's suites and every backend package's suites.
        // Nothing that ships links it.
        .library(name: "ZephraTestSupport", targets: ["ZephraTestSupport"]),
    ],
    targets: [
        .target(name: "ZephraCore"),
        .target(name: "ZephraSnapshot", dependencies: ["ZephraCore"]),
        .target(name: "ZephraEngine", dependencies: ["ZephraCore", "ZephraSnapshot"]),
        // ZephraCore for `ClipEditing`, the seam the engine reads clips back through.
        .target(name: "ZephraMedia", dependencies: ["ZephraCore"]),
        // ZephraCore for the catalog and the models folder: SnapshotUnderTest looks where the app
        // would have built or downloaded a model before it looks in the hub cache.
        .target(name: "ZephraTestSupport", dependencies: ["ZephraCore"]),
        .testTarget(name: "ZephraCoreTests", dependencies: ["ZephraCore"]),
        .testTarget(
            name: "ZephraMediaTests", dependencies: ["ZephraMedia", "ZephraCore"],
            resources: [.copy("Fixtures")]),
        .testTarget(
            name: "ZephraSnapshotTests",
            dependencies: ["ZephraSnapshot", "ZephraCore", "ZephraTestSupport"]
        ),
        .testTarget(
            name: "ZephraEngineTests",
            dependencies: ["ZephraEngine", "ZephraCore", "ZephraSnapshot", "ZephraTestSupport"]
        ),
    ]
)
