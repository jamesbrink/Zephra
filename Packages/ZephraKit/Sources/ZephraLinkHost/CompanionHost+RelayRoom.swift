import Foundation
import ZephraLinkProtocol

/// Who the relay lets into this Mac's room: the devices it has paired, and — while a code is on
/// screen — anybody at all.
///
/// The relay is not a trust boundary and never has been; what it decides is who may spend this
/// Mac's socket. Two answers, and the road republishes both whenever either moves.
extension CompanionHost {
    /// The signing keys the relay admits a guest out of.
    ///
    /// Every paired device, the most recently seen first, and at most `RelayJoin.allowLimit` of
    /// them, which is all the relay will take: a Mac with more phones than that admits the ones
    /// actually in use rather than whichever the keychain happened to list first. An empty list
    /// admits nobody, which is what a Mac that has paired nothing should do.
    public var relayAllowList: [Data] {
        devices
            .sorted { ($0.lastSeen ?? $0.pairedAt) > ($1.lastSeen ?? $1.pairedAt) }
            .prefix(RelayJoin.allowLimit)
            .map(\.keys.signing)
    }

    /// Declares the room open for as long as the code is good for.
    ///
    /// The clock is the only thing that shuts a room nobody took down: a code expires on its own
    /// after two minutes, and a room left open until somebody pressed something would be open for
    /// as long as the Mac ran.
    func openRoom(until expiry: Date) {
        openRoomClock?.cancel()
        relayOpen = true
        openRoomClock = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(expiry.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled, let self, secret?.isExpired() != false else { return }
            shutRoom()
        }
    }

    /// Shuts it again, whatever it was that took the code down: the person, a pairing that
    /// succeeded, three wrong answers, or the code simply running out.
    func shutRoom() {
        openRoomClock?.cancel()
        openRoomClock = nil
        relayOpen = false
    }
}
