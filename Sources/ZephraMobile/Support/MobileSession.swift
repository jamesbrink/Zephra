import Observation
import ZephraLinkProtocol

/// Everything the phone knows about the Mac it is looking at, and the one door a pairing code
/// goes in through.
///
/// Five facts and a closure, deliberately. The real client — `LinkClient`, which owns the
/// socket, the channel and the deltas — is being built beside this and will take this type's
/// place; every view reads the Mac through these five properties and nothing else, so that
/// swap is one file changed rather than a sweep through the interface.
@MainActor
@Observable
final class MobileSession {
    /// What the paired Mac is called, or nil while no Mac has been paired: the whole of the
    /// decision between the pairing screen and the app.
    var pairedHostName: String?
    /// The Mac's state as of the last message, or nil before the first one has landed.
    var snapshot: StateSnapshot?
    /// The page of the Mac's library the phone is holding.
    var library: [LibraryEntry]
    /// Whether the connection is up right now. A paired Mac that is asleep or off the network
    /// is still paired; this is what says the numbers on screen are current.
    var isLive: Bool
    /// What to do with a code the person scanned, pasted or opened. Injected, so the pairing
    /// screen knows how to hand a payload over without knowing what happens to it.
    var onPair: (PairingPayload) async throws -> Void

    /// Creates a session. The default `onPair` does nothing, which is what the frozen preview
    /// states want; the composition root passes the real one.
    init(
        pairedHostName: String? = nil,
        snapshot: StateSnapshot? = nil,
        library: [LibraryEntry] = [],
        isLive: Bool = false,
        onPair: @escaping (PairingPayload) async throws -> Void = { _ in }
    ) {
        self.pairedHostName = pairedHostName
        self.snapshot = snapshot
        self.library = library
        self.isLive = isLive
        self.onPair = onPair
    }

    /// Whether a Mac has been paired, which is what decides whether the pairing screen is up.
    var isPaired: Bool { pairedHostName != nil }
}
