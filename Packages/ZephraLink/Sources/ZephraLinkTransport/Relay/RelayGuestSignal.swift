import Foundation
import ZephraLinkProtocol

/// What a host's road heard, and which guest of the room it was about.
///
/// The Mac has one socket for every phone in its room, so a frame and a peer notice mean nothing
/// without the guest the relay wrote on them. One stream rather than two, because the order
/// matters: a `peer left` that overtook the frames behind it would end a session still being
/// read from.
///
/// Nil is a relay that names nobody — the build before guests were counted — and is the room's
/// one guest, which is what keeps an older relay working unchanged.
enum RelayGuestSignal: Sendable {
    /// One sealed frame from a guest, whole.
    case frame(Data, from: String?)
    /// A guest arrived or went.
    case peer(RelayPeerEvent, from: String?)
}
