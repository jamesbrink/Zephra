// swift-tools-version: 6.0
import PackageDescription

// The chrome both apps draw with: the radii, hairlines and heights in `ZephraChrome`, the
// washes laid over things, the palette's colour sets, and the handful of badges that are
// nothing but those numbers. SwiftUI and ZephraCore only, and iOS as well as macOS, because
// the companion app must look like the same program rather than resemble it.
let package = Package(
    name: "ZephraStyle",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ZephraStyle", targets: ["ZephraStyle"])
    ],
    dependencies: [
        // For `ModelCatalog`, which decides a model's dot, and `DurationLabel`, which spells a
        // clip's length on its badge. Nothing else from the value layer.
        .package(path: "../ZephraKit")
    ],
    targets: [
        .target(
            name: "ZephraStyle",
            dependencies: [.product(name: "ZephraCore", package: "ZephraKit")],
            // The colour sets, so light and dark come for free and both apps read the same
            // amber. Processed rather than copied: an asset catalog is compiled.
            resources: [.process("Resources")]
        )
    ]
)
