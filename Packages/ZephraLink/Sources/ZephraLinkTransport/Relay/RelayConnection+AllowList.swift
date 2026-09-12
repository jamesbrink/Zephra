import Foundation
import ZephraLinkProtocol

/// What a host tells the relay about who may join its room.
extension RelayConnection {
    /// Replaces the set of guests the relay will admit into this room, and says whether the room
    /// is open to a guest on no list at all.
    ///
    /// Kept here rather than handed in at `init` because both move while the socket is up: a
    /// pairing completes, a device is revoked, a code goes up or comes down. Called before
    /// `start()` it is what the join carries; called after, it goes as its own message. A guest
    /// sends none of this, and the relay ignores either from anything but the host that owns the
    /// room.
    public func updateAllowList(_ keys: [Data], open: Bool = false) async {
        let trimmed = Array(keys.prefix(RelayJoin.allowLimit))
        let isLive = lock.withLock { () -> Bool in
            state.allow = trimmed
            state.isOpen = open
            return state.isJoined && !state.isClosed
        }
        guard isLive, role == .host else { return }
        // `write` logs its own failure: an allow-list that never reached the relay is a phone
        // that cannot join, and it used to be swallowed here without a word.
        try? await write(.allow(pubs: trimmed, open: open ? true : nil))
    }
}
