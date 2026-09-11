import Foundation
import ZephraLinkClient
import ZephraLinkProtocol

/// Every road but the relay, closed, so a phone sitting beside the Mac takes the road a phone in
/// another country would.
///
/// The relay is the last road tried and the hardest to get in front of: a phone on the same
/// Wi-Fi reaches the Mac on its first stored address and never asks the relay anything. So the
/// only honest way to exercise that road is to take the others away — which is what this does,
/// by refusing a browse and failing every LAN endpoint, so `connect()` and `pair(with:)` walk
/// their list and fall through to `connectRelay` exactly as they would from a hotel.
///
/// A decorator here rather than a flag inside `NetworkLinkRoads`, for the reason the composition
/// root exists: which roads a phone has is the root's business, and the link package has none.
/// Debug only, and read once at launch beside `ZEPHRA_PREVIEW_STATE`.
nonisolated struct RelayOnlyRoads: LinkRoads {
    /// Whether this launch asked for the relay and nothing else.
    ///
    /// `ZEPHRA_FORCE_RELAY=1`. Inert in Release, exactly as `MobilePreview.state` is: a shipped
    /// phone that could be talked out of its local network would be slower for no reason.
    static let isRequested: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["ZEPHRA_FORCE_RELAY"] == "1"
        #else
        return false
        #endif
    }()

    /// The real roads, for the one road left open.
    let roads: any LinkRoads

    /// No Mac is ever found nearby, and the stream finishes at once rather than running out the
    /// browse window: the point is to reach the relay quickly, not to sit through a timeout.
    func browse() -> AsyncStream<[LinkCandidate]> {
        AsyncStream { $0.finish() }
    }

    func connect(_ candidate: LinkCandidate) async throws -> any LinkConnection {
        throw LinkClientError.unreachable
    }

    func connectLAN(_ endpoint: Endpoint) async throws -> any LinkConnection {
        throw LinkClientError.unreachable
    }

    func connectRelay(room: RoomID) async throws -> any LinkConnection {
        try await roads.connectRelay(room: room)
    }
}
