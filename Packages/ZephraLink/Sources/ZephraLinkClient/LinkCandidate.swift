import ZephraLinkProtocol

/// One Mac a browse turned up, as the client knows it.
///
/// No endpoint in it: an address is the road's business, and a Bonjour service is resolved by
/// Network at the moment a connection is made rather than named in advance. What the client
/// needs is the name to show and the room to match a pairing against, and the roads hand back
/// a connection when given the candidate back.
public struct LinkCandidate: Hashable, Sendable, Identifiable {
    /// What the road calls it, which is what `LinkRoads.connect(_:)` looks it up by.
    public let id: String
    /// What the Mac is called.
    public let name: String
    /// The room its TXT record named, or nil where it published none.
    public let roomID: RoomID?

    /// Creates a candidate.
    public init(id: String, name: String, roomID: RoomID?) {
        self.id = id
        self.name = name
        self.roomID = roomID
    }
}
