import Foundation
import ZephraLinkProtocol
import ZephraLinkTransport

/// One join of one relay room, as `RelayRoad` uses it.
///
/// `RelayListener` is the only thing that implements it, and the point is not a second
/// implementation: it is that the road above can be tested without a socket. What the road has to
/// get right is the order of two calls — the allow-list and the open flag go in *before* the join
/// is made, since a join that carries an empty list is a room that admits nobody until a second
/// message lands, and the phone that dialled in between is told `not allowed` for its trouble.
/// A double that records what it was told and when is what pins that.
nonisolated protocol RelayJoining: Sendable {
    /// Replaces the keys this room admits, and whether it is open to a key on no list.
    func updateAllowList(_ keys: [Data], open: Bool) async
    /// Joins the room.
    func start() async throws
    /// Every guest of this join, until the road under it goes.
    func connections() -> AsyncStream<any LinkConnection>
    /// Leaves the room.
    func stop() async
}

extension RelayListener: RelayJoining {}
