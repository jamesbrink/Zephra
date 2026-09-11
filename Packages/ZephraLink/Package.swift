// swift-tools-version: 6.0
import PackageDescription

// The protocol the Mac app and the phone both speak. One target for now: the wire types, the
// secure channel and the pairing payload, with no transport and no interface in it, so both
// ends can be tested without a socket and the iOS app can link it whole.
let package = Package(
    name: "ZephraLink",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ZephraLinkProtocol", targets: ["ZephraLinkProtocol"])
    ],
    dependencies: [
        .package(path: "../ZephraKit")
    ],
    targets: [
        // ZephraCore for the settings, the size and the capabilities a request is made of;
        // ZephraEngine for `GenerationRecord` and `LibraryAnnotation` alone, which are the
        // on-disk truth inside every PNG. Mirroring either of those on the wire would give the
        // library two shapes that could drift apart, so the wire carries the real ones.
        .target(
            name: "ZephraLinkProtocol",
            dependencies: [
                .product(name: "ZephraCore", package: "ZephraKit"),
                .product(name: "ZephraEngine", package: "ZephraKit"),
            ]
        ),
        .testTarget(name: "ZephraLinkProtocolTests", dependencies: ["ZephraLinkProtocol"]),
    ]
)
