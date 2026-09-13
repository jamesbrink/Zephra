import Foundation
import Observation
import ZephraLinkProtocol
import os

/// The one object the phone's views observe: a Mac at the other end of a road, and its state.
///
/// `GenerationStore`'s counterpart on the phone, and split the same way — a file per concern,
/// never more lines in this one. What it holds is what the Mac published: a snapshot brought up
/// to date by the deltas after it, the newest preview frame, and the library as far as the
/// phone has been told about it. Nothing here decides anything about a generation; the Mac
/// clamps, the Mac queues, and the phone shows what came back.
@MainActor
@Observable
public final class LinkClient {
    /// How long a command may go unanswered before the phone gives up on it.
    public static let requestTimeout: Duration = .seconds(30)
    /// How long a transfer may go without a chunk before the phone gives up on it.
    ///
    /// **Idle time, not a wall clock.** It was two minutes from the announcement, which a 40 MB
    /// clip over a paced relay road legitimately passes and a transfer that died at chunk 630
    /// spends sitting there doing nothing. Re-armed by every chunk accepted, fifteen seconds is
    /// far longer than any gap the road and the cadence between them can open, and short enough
    /// that a transfer nothing is going to finish is asked for again rather than waited out.
    public static let blobIdleTimeout: Duration = .seconds(15)
    /// How many **unsolicited** blobs may be part way through at once. The oldest is dropped past
    /// this. A blob the phone asked for is not in this count: the limit is there to bound what a
    /// Mac can make this phone hold, and the grid announcing five thumbnails used to evict the
    /// 40 MB clip somebody was waiting on.
    public static let blobLimit = 4
    /// How many times one `fetchBlob` asks before it gives up. Each attempt after the first
    /// carries on from the chunk the one before it reached, so four attempts is four holes
    /// survived rather than four whole files.
    public static let blobAttempts = 4
    /// How long the local network gets before the relay is tried: every stored address and every
    /// Mac Bonjour turns up in the room are dialled at once inside it (`LocalRoadRace`), and a
    /// Mac on the same network answers in a fraction of it.
    public static let lanWindow: Duration = .seconds(3)

    /// Where the connection has got to.
    public internal(set) var connection: LinkConnectionState = .offline
    /// Why the last pairing ended at the Mac's end, in words for the pairing screen, or nil.
    ///
    /// Set when a Mac this phone was paired with withdraws it — an error frame on a live
    /// session, or a refusal on a reconnect — and cleared when the person pairs again or
    /// forgets the Mac themselves. The pairing screen shows it, so a phone that was revoked
    /// says so rather than "offline".
    public internal(set) var farewell: String?
    /// The Mac's whole state, as of the last snapshot and every delta since.
    public internal(set) var snapshot: StateSnapshot?
    /// The newest frame of the run in flight, cleared when the Mac says the engine is not busy
    /// and at no other time: a link that drops under a run that is still going leaves the frame
    /// on screen, which is a truer picture than the spinner it used to fall back to.
    public internal(set) var preview: PreviewFrameDTO?
    /// The library, as far as the Mac has said and the phone has asked.
    public internal(set) var library: [LibraryEntry] = []
    /// Whether `library` is the whole of the Mac's folder rather than a window onto it.
    ///
    /// False on every new session and true once the pull that follows a snapshot has read the
    /// last page. It is the cache's answer to a question the counts cannot settle: the Mac sends
    /// at most a hundred entries in a reset, so a phone comparing what it holds against
    /// `StateSnapshot.libraryCount` cannot tell a short listing from a complete one, and a
    /// removal applied on that comparison throws away pictures that are still there.
    public internal(set) var libraryIsComplete = false
    /// The Mac this phone knows, or nil before it has paired with one.
    public internal(set) var pairedHost: PairedHost?

    @ObservationIgnored let transferOwner = UUID()
    @ObservationIgnored let transferAdmission: TransferAdmission
    @ObservationIgnored let blobBudget: BlobBudget
    @ObservationIgnored let store: any LinkKeyStore
    @ObservationIgnored let roads: any LinkRoads
    @ObservationIgnored let deviceName: String
    @ObservationIgnored let logger = Logger(subsystem: "io.zephra", category: "link.client")
    @ObservationIgnored var identity: DeviceIdentity
    @ObservationIgnored var session: LinkSession?
    @ObservationIgnored var pending: [UUID: CheckedContinuation<Reply, any Error>] = [:]
    @ObservationIgnored var blobs: [UUID: BlobReassembly] = [:]
    /// The order they were announced in, so the one dropped at the limit is the oldest and not
    /// whichever the dictionary happened to hand back first.
    @ObservationIgnored var blobOrder: [UUID] = []
    @ObservationIgnored var blobWaiters: [UUID: CheckedContinuation<Data, any Error>] = [:]
    @ObservationIgnored var arrivedBlobs: [UUID: Data] = [:]
    /// The transfers this phone actually asked for, which are the only ones worth keeping a
    /// partial of. A Mac announcing unsolicited blobs and sending one chunk of each would
    /// otherwise park a resumption apiece for the length of the session, and nobody would ever
    /// come to collect them. `blobWaiters` cannot answer this: a wanted transfer can fail in the
    /// window between its announcement and the `await` that registers a waiter for it.
    @ObservationIgnored var wantedBlobs: Set<UUID> = []
    /// What survived of a transfer that stopped, by the blob it was, until the attempt that was
    /// waiting on it picks it up. `arrivedBlobs`' shape and for its reason: the failure and the
    /// `await` for it are two turns of the main actor either way round.
    @ObservationIgnored var salvaged: [UUID: BlobResumption] = [:]
    /// What a request in flight is asking to carry on from, by the envelope that asked. Read
    /// where the reply's announcement opens the transfer, which is the only place that knows the
    /// new blob's id and the old blob's bytes at the same moment.
    @ObservationIgnored var resumptions: [UUID: BlobResumption] = [:]
    @ObservationIgnored var timers: [UUID: Task<Void, Never>] = [:]
    /// The pull reading the library across, one per session.
    @ObservationIgnored var libraryMutation = 0
    @ObservationIgnored var libraryPull: Task<Void, Never>?
    /// How far that pull has got, or nil when none is running. What a fresh snapshot on the
    /// same session is measured against, so a resync does not start the library again.
    @ObservationIgnored var libraryProgress: LibraryPullProgress?
    @ObservationIgnored var isFrozen = false
    /// How long a session's `OrderedInbox` holds a gap open before it calls it loss. A property
    /// rather than the constant so a suite can ask the question in milliseconds.
    @ObservationIgnored var frameHold: Duration = OrderedInbox.hold
    /// How long a command may go unanswered before this end gives up on it. A property rather
    /// than the constant for the reason `frameHold` is one, and it carries more weight now: a
    /// reply a hole swallowed is closed by this clock rather than by the gap, so a suite that
    /// asks what a lost reply costs has to be able to ask it in milliseconds.
    @ObservationIgnored var requestTimeout: Duration = LinkClient.requestTimeout
    /// Every time a session ended, so whoever reconnects starts at once rather than on the next
    /// beat of a poll. Newest-only: what a waiter needs to know is that the session it was
    /// sitting on is gone, not how many have been.
    @ObservationIgnored private let endings: AsyncStream<Void>
    @ObservationIgnored private let endingSink: AsyncStream<Void>.Continuation

    /// Takes the device's identity and its pairing out of the store, making an identity the
    /// first time there is none: a new identity every launch would look like a new device and
    /// every pairing would be gone.
    public init(store: any LinkKeyStore, roads: any LinkRoads, deviceName: String,
                transferAdmission: TransferAdmission? = nil, blobBudget: BlobBudget? = nil) {
        self.transferAdmission = transferAdmission ?? TransferAdmission()
        self.blobBudget = blobBudget ?? BlobBudget()
        (endings, endingSink) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.store = store
        self.roads = roads
        self.deviceName = deviceName
        if let existing = try? store.loadIdentity() {
            identity = existing
        } else {
            let fresh = DeviceIdentity()
            try? store.save(fresh)
            identity = fresh
        }
        pairedHost = (try? store.loadPairedHost()) ?? nil
    }

    /// This device's published keys, which is what a Mac is shown while it asks to pair.
    public var publicKeys: DevicePublicKeys { identity.publicKeys }

    /// A session ending, as it happens. `LinkReconnect` waits on this instead of asking every
    /// couple of seconds whether the Mac is still there, so a socket that died mid-session —
    /// which over the relay is how a sleeping Mac looks — is reconnected to immediately.
    ///
    /// One consumer: an `AsyncStream` has one, and an iterator that is dropped ends the stream
    /// behind it, so whoever waits keeps the iterator it made.
    public func sessionEndings() -> AsyncStream<Void> { endings }

    /// Says the session that was live has gone. Called wherever one is let go, which is also
    /// where the library pull is stopped: the next session's snapshot starts a new one.
    func sessionEnded() {
        endLibraryPull()
        endingSink.yield(())
    }

    /// A client that shows one state and touches no network, for a preview or a screenshot.
    ///
    /// Requests answer `.ok` and blobs fail: a preview that could make a request would be a
    /// preview that could queue a generation on somebody's Mac.
    ///
    /// It is paired, because every state worth photographing is a paired one — the Mac named
    /// in the snapshot, with a throwaway identity's keys and no endpoint, kept in a store that
    /// ends with the process. The connection rides in so a screenshot can be taken of a phone
    /// whose Mac is not answering, which is the one state a live client cannot be asked for,
    /// and a preview frame rides in for the same reason: the canvas mid-run is a frame, and a
    /// frozen client has no session to be sent one over.
    public static func frozen(
        snapshot: StateSnapshot, library: [LibraryEntry],
        connection: LinkConnectionState = .live(.lan),
        preview: PreviewFrameDTO? = nil
    ) -> LinkClient {
        let client = LinkClient(
            store: MemoryLinkKeyStore(), roads: MemoryLinkRoads.unreachable(),
            deviceName: "Preview")
        client.isFrozen = true
        client.snapshot = snapshot
        client.library = library
        client.libraryIsComplete = true
        client.connection = connection
        client.preview = preview
        let host = DeviceIdentity()
        client.pairedHost = PairedHost(
            name: snapshot.hostName, keys: host.publicKeys, endpoints: [], roomID: host.roomID,
            pairedAt: Date())
        return client
    }
}
