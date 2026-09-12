import ZephraLinkProtocol

/// Every way the client may reach a Mac, as one injected thing.
///
/// The client never names `TCPConnection` or `RelayConnection`. That is what lets its whole
/// session — the handshake, the dispatch, the requests and the blobs — be tested against two
/// ends of a road that never leaves the process, in milliseconds and with no permission dialog
/// for the local network.
public protocol LinkRoads: Sendable {
    /// Macs on the local network, as the list changes; the stream finishes when looking stops.
    func browse() -> AsyncStream<[LinkCandidate]>
    /// A road to one of them.
    func connect(_ candidate: LinkCandidate) async throws -> any LinkConnection
    /// A road straight to an address off a pairing code.
    func connectLAN(_ endpoint: Endpoint) async throws -> any LinkConnection
    /// A road through the relay to a room.
    ///
    /// `pairing` is what a phone reading a code is doing, and it changes one answer: the relay
    /// refusing a key it does not have on its list is worth telling a person about while they are
    /// holding a code up to a Mac, and is worth nothing at all on a reconnection, where the list
    /// is simply a moment out of date.
    func connectRelay(room: RoomID, pairing: Bool) async throws -> any LinkConnection
}
