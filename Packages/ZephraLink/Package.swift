// swift-tools-version: 6.0
import PackageDescription

// The protocol the Mac app and the phone both speak, the roads it travels, and the phone's
// client over them. Three targets, so the wire types stay testable without a socket and the
// client stays testable without a network: the protocol knows nothing of Network.framework,
// the transport knows nothing of the client's state, and the client reaches a road only
// through a protocol it can be handed a double for.
let package = Package(
    name: "ZephraLink",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ZephraLinkProtocol", targets: ["ZephraLinkProtocol"]),
        .library(name: "ZephraLinkTransport", targets: ["ZephraLinkTransport"]),
        .library(name: "ZephraLinkClient", targets: ["ZephraLinkClient"]),
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
        // The roads: TCP on the local network, Bonjour to find one, and the relay's WebSocket
        // when neither end can reach the other. Network and os over the protocol, and no
        // state: everything here is a `LinkConnection` or something that makes one.
        .target(name: "ZephraLinkTransport", dependencies: ["ZephraLinkProtocol"]),
        // The phone's side: one observable object over a road, holding the Mac's state.
        .target(
            name: "ZephraLinkClient",
            dependencies: ["ZephraLinkProtocol", "ZephraLinkTransport"]
        ),
        .testTarget(name: "ZephraLinkProtocolTests", dependencies: ["ZephraLinkProtocol"]),
        .testTarget(name: "ZephraLinkTransportTests", dependencies: ["ZephraLinkTransport"]),
        .testTarget(
            name: "ZephraLinkClientTests",
            dependencies: ["ZephraLinkClient", "ZephraLinkTransport"]
        ),
    ]
)
