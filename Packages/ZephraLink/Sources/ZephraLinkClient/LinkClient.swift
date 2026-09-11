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
    /// How long the bytes of a blob may take after the reply that announced them.
    public static let blobTimeout: Duration = .seconds(120)
    /// How long a browse runs before the relay is tried.
    public static let browseWindow: Duration = .seconds(3)

    /// Where the connection has got to.
    public internal(set) var connection: LinkConnectionState = .offline
    /// The Mac's whole state, as of the last snapshot and every delta since.
    public internal(set) var snapshot: StateSnapshot?
    /// The newest frame of the run in flight, cleared whenever a run ends or the link does.
    public internal(set) var preview: PreviewFrameDTO?
    /// The library, as far as the Mac has said.
    public internal(set) var library: [LibraryEntry] = []
    /// The Mac this phone knows, or nil before it has paired with one.
    public internal(set) var pairedHost: PairedHost?

    @ObservationIgnored let store: any LinkKeyStore
    @ObservationIgnored let roads: any LinkRoads
    @ObservationIgnored let deviceName: String
    @ObservationIgnored let logger = Logger(subsystem: "io.zephra", category: "link.client")
    @ObservationIgnored var identity: DeviceIdentity
    @ObservationIgnored var session: LinkSession?
    @ObservationIgnored var pending: [UUID: CheckedContinuation<Reply, any Error>] = [:]
    @ObservationIgnored var blobs: [UUID: BlobReassembly] = [:]
    @ObservationIgnored var blobWaiters: [UUID: CheckedContinuation<Data, any Error>] = [:]
    @ObservationIgnored var arrivedBlobs: [UUID: Data] = [:]
    @ObservationIgnored var timers: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var isFrozen = false

    /// Takes the device's identity and its pairing out of the store, making an identity the
    /// first time there is none: a new identity every launch would look like a new device and
    /// every pairing would be gone.
    public init(store: any LinkKeyStore, roads: any LinkRoads, deviceName: String) {
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

    /// A client that shows one state and touches no network, for a preview or a screenshot.
    ///
    /// Requests answer `.ok` and blobs fail: a preview that could make a request would be a
    /// preview that could queue a generation on somebody's Mac.
    ///
    /// It is paired, because every state worth photographing is a paired one — the Mac named
    /// in the snapshot, with a throwaway identity's keys and no endpoint, kept in a store that
    /// ends with the process. The connection rides in so a screenshot can be taken of a phone
    /// whose Mac is not answering, which is the one state a live client cannot be asked for.
    public static func frozen(
        snapshot: StateSnapshot, library: [LibraryEntry],
        connection: LinkConnectionState = .live(.lan)
    ) -> LinkClient {
        let client = LinkClient(
            store: MemoryLinkKeyStore(), roads: MemoryLinkRoads.unreachable(),
            deviceName: "Preview")
        client.isFrozen = true
        client.snapshot = snapshot
        client.library = library
        client.connection = connection
        let host = DeviceIdentity()
        client.pairedHost = PairedHost(
            name: snapshot.hostName, keys: host.publicKeys, endpoints: [], roomID: host.roomID,
            pairedAt: Date())
        return client
    }
}
