// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZephraKit",
    // iOS as well, because the value layer the companion app reads — the catalog, the
    // capabilities, and the three parsers that turn typing into them — is the same layer.
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ZephraCore", targets: ["ZephraCore"]),
        .library(name: "ZephraSnapshot", targets: ["ZephraSnapshot"]),
        .library(name: "ZephraEngine", targets: ["ZephraEngine"]),
        // The Mac's side of the companion link: the sessions a paired phone talks through and
        // the projections that turn the store and the index into what crosses the wire.
        .library(name: "ZephraLinkHost", targets: ["ZephraLinkHost"]),
        // Frames in, an MP4 out. Foundation and AVFoundation, no MLX, so a video backend and
        // the app share one writer and `make test` covers it.
        .library(name: "ZephraMedia", targets: ["ZephraMedia"]),
        // Test fixtures shared by this package's suites and every backend package's suites.
        // Nothing that ships links it.
        .library(name: "ZephraTestSupport", targets: ["ZephraTestSupport"]),
    ],
    // ZephraLink depends on this package for ZephraCore and ZephraEngine, and ZephraLinkHost
    // depends on ZephraLink for the wire. That is a cycle between two *packages* and not
    // between any two targets — ZephraLinkProtocol -> ZephraEngine, ZephraLinkHost ->
    // ZephraLinkProtocol — which is what SwiftPM actually resolves, so it builds. The host
    // lives here rather than in ZephraLink because it is Mac-only and reaches deep into the
    // engine, and because ZephraLink is the one package an iOS app links whole.
    dependencies: [
        .package(path: "../ZephraLink")
    ],
    targets: [
        .target(name: "ZephraCore"),
        .target(name: "ZephraSnapshot", dependencies: ["ZephraCore"]),
        .target(name: "ZephraEngine", dependencies: ["ZephraCore", "ZephraSnapshot"]),
        // ZephraCore for `ClipEditing`, the seam the engine reads clips back through.
        .target(name: "ZephraMedia", dependencies: ["ZephraCore"]),
        // ImageIO and CoreGraphics for the one thing the host encodes itself: a preview frame
        // as JPEG. No UI framework, which `make lint-layers` keeps out of this package.
        .target(
            name: "ZephraLinkHost",
            dependencies: [
                "ZephraCore", "ZephraEngine",
                .product(name: "ZephraLinkProtocol", package: "ZephraLink"),
            ]
        ),
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
            // The companion host's suites live here rather than beside the host, because what
            // they drive is `EngineTestBed` and `MockBackend`: a session is only worth testing
            // against a store that really queues, saves and finishes.
            dependencies: [
                "ZephraEngine", "ZephraCore", "ZephraSnapshot", "ZephraTestSupport",
                "ZephraLinkHost", .product(name: "ZephraLinkProtocol", package: "ZephraLink"),
            ]
        ),
    ]
)
