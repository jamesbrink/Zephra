import Foundation
import Network
import ZephraLinkProtocol

/// One Mac seen on the local network.
///
/// The endpoint is the service itself, not an address: Network resolves a `.service` endpoint
/// when a connection to it is made, over whichever interface and address family actually works,
/// which is a better answer than any one address a browse could hand back.
public struct DiscoveredHost: Hashable, Sendable, Identifiable {
    /// The Bonjour instance name, which is what the Mac is called.
    public let name: String
    /// The room its TXT record names, or nil where it published none.
    public let roomID: RoomID?
    /// Where to connect, left as a service for Network to resolve.
    public let endpoint: NWEndpoint

    /// Creates a result.
    public init(name: String, roomID: RoomID?, endpoint: NWEndpoint) {
        self.name = name
        self.roomID = roomID
        self.endpoint = endpoint
    }

    /// The instance name is the identity: Bonjour keeps it unique inside a domain.
    public var id: String { name }
}
