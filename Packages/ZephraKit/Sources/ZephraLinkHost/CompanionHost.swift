import Foundation
import Observation
import ZephraEngine
import ZephraLinkProtocol
import os

/// The Mac's side of the companion link: every phone session, the pairings behind them, and the
/// one loop that watches the store and the index for what to tell them.
///
/// It reads the two observable objects the interface reads and writes to neither. Everything a
/// phone may ask for goes through `GenerationStore.enqueue` and the index's own mutations, which
/// are the same doors the Mac's own menus use; the capsule, the canvas and the query are the
/// person's at the keyboard and are never touched from here. What it owns is the sessions, the
/// paired devices, and the pairing secret that is live while a code is on screen.
///
/// Several listeners may be served at once — a TCP listener on the local network and a relay
/// connection from outside it — because a session does not know or care which road it came in
/// on: the handshake and the channel are the same either way.
@MainActor
@Observable
public final class CompanionHost {
    /// The sessions talking right now. Observable so Settings can say how many phones are
    /// connected without asking for the sessions themselves.
    public internal(set) var sessions: [CompanionSession] = []
    /// Every device paired with this Mac, as the Settings list draws them.
    public internal(set) var devices: [PairedDevice] = []
    /// The code on screen, or nil when none is. The payload rather than the secret, because
    /// what a view wants is the QR's contents and the expiry to count down to.
    public internal(set) var pairing: PairingPayload?
    /// One line saying why the code went, where it went for a reason of its own. Cleared the
    /// moment a fresh code goes up.
    public internal(set) var pairingNote: String?
    /// Whether the relay room admits a guest on no allow-list: true exactly while a code is on
    /// screen, since a first pairing is a phone with no key anywhere. `CompanionHost+RelayRoom`.
    public internal(set) var relayOpen = false

    /// How many wrong answers to one code end the pairing.
    ///
    /// The secret behind a code is guessed at by trying, and a code that stays up while
    /// something tries is a code somebody is working through: three is enough for a person who
    /// scanned a stale screenshot and far too few to search.
    public static let pairingAttemptLimit = 3

    /// What the Mac is called on the phone's list of Macs.
    @ObservationIgnored public let hostName: String

    /// How long a connection may sit in the plaintext stage before it is closed. An instance
    /// property rather than a constant so a suite can ask the question in milliseconds.
    @ObservationIgnored var handshakeDeadline: Duration = .seconds(10)

    /// How long a session's `OrderedInbox` holds a gap open before it calls it loss, handed to
    /// each session as its channel is made. An instance property for the same reason.
    @ObservationIgnored var frameHold: Duration = OrderedInbox.hold

    @ObservationIgnored let store: GenerationStore
    @ObservationIgnored let index: LibraryIndex
    @ObservationIgnored let thumbnails: any ThumbnailSupply
    @ObservationIgnored let identity: DeviceIdentity
    @ObservationIgnored let pairings: any PairingStore
    @ObservationIgnored let endpoints: @MainActor () -> [Endpoint]
    @ObservationIgnored let logger = Logger(subsystem: "io.zephra", category: "companion")

    /// The secret behind the code on screen, live for two minutes. Apart from `pairing` because
    /// the bytes are not something a view should be able to read off the host.
    @ObservationIgnored var secret: PairingSecret?
    /// How many devices have answered this code wrongly.
    @ObservationIgnored var pairingFailures = 0
    /// The clock that shuts the room when the code runs out, since nothing else would ask.
    @ObservationIgnored var openRoomClock: Task<Void, Never>?
    @ObservationIgnored var listeners: [any LinkListener] = []
    @ObservationIgnored var serving: [Task<Void, Never>] = []
    /// The observation loop, running only while at least one session is listening.
    @ObservationIgnored var observation: Task<Void, Never>?
    /// What the sessions were last told, so a delta is published for what actually moved.
    @ObservationIgnored var published = CompanionPublication()
    /// True for the one pass that fills that record without sending any of it, which is how the
    /// loop starts without repeating the snapshot a session has just been given.
    @ObservationIgnored var isSeeding = false

    /// Builds the host over the two objects the interface observes.
    ///
    /// `endpoints` is a closure rather than a list because the addresses a QR code should carry
    /// are the ones the Mac has when the code goes up, which is not when the host was built: a
    /// laptop that has moved between two networks since launch would otherwise publish the one
    /// it is no longer on.
    public init(
        store: GenerationStore,
        index: LibraryIndex,
        thumbnails: any ThumbnailSupply,
        identity: DeviceIdentity,
        pairings: any PairingStore,
        hostName: String,
        devices: [PairedDevice]? = nil,
        endpoints: @escaping @MainActor () -> [Endpoint] = { [] }
    ) {
        self.store = store
        self.index = index
        self.thumbnails = thumbnails
        self.identity = identity
        self.pairings = pairings
        self.hostName = hostName
        self.endpoints = endpoints
        // The list may be handed in already read. A keychain read is a call that can stop for
        // as long as a person takes to answer a system prompt, and this initialiser runs on the
        // main actor, so a caller that has somewhere else to read it passes it here instead.
        self.devices = devices ?? ((try? pairings.load()) ?? [])
    }

    /// The Mac's published keys, which a phone needs to know before it can knock.
    public var publicKeys: DevicePublicKeys { identity.publicKeys }

    /// Takes every connection `listener` yields, for the life of the returned task.
    ///
    /// The task is handed back so a caller can cancel one road without stopping the host; it is
    /// also held here, so `stop()` takes it down with the rest.
    @discardableResult
    public func serve(_ listener: any LinkListener) -> Task<Void, Never> {
        listeners.append(listener)
        let task = Task { @MainActor [weak self] in
            for await connection in listener.connections() {
                guard !Task.isCancelled, let self else { break }
                accept(connection)
            }
        }
        serving.append(task)
        return task
    }

    /// Closes every session and stops accepting new ones.
    ///
    /// Listeners are stopped first, so nothing arrives while the sessions are being closed and
    /// the host is not left holding a connection nobody is reading.
    public func stop() async {
        for task in serving { task.cancel() }
        for listener in listeners { await listener.stop() }
        listeners.removeAll()
        for task in serving { await task.value }
        serving.removeAll()
        let closing = sessions
        sessions.removeAll()
        for session in closing { await session.close() }
        endPairing()
        stopObserving()
    }

    /// Takes a session off the list once it has closed, and stops watching when it was the last.
    func forget(_ session: CompanionSession) {
        sessions.removeAll { $0 === session }
        if sessions.isEmpty { stopObserving() }
    }
}
