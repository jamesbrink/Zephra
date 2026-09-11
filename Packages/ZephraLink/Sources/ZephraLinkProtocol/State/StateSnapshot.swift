import Foundation

/// The whole of the Mac's state, sent once when a session opens.
///
/// One message rather than a dozen, because a phone with half a state cannot draw anything: the
/// snapshot is what makes the first frame correct, and every `StateDelta` after it is an edit
/// to this. A phone that misses a delta asks for a snapshot again rather than reconciling.
public struct StateSnapshot: Codable, Hashable, Sendable {
    /// Which protocol this Mac speaks, repeated here so a snapshot read from a log says.
    public var protocolVersion: Int
    /// What the Mac is called, as it appears on the phone's list of Macs.
    public var hostName: String
    /// The model in force.
    public var model: ModelSummary
    /// Every model the catalog holds, in the order the Mac lists them.
    public var models: [ModelSummary]
    /// Where the engine is.
    public var engine: EngineStateDTO
    /// What is waiting, in order.
    public var queue: [QueuedEntry]
    /// What is being rendered, or nil.
    public var running: QueuedEntry?
    /// What this session has finished, newest first.
    public var history: [HistoryEntry]
    /// Whether each model's weights are here, keyed by descriptor identifier.
    public var availability: [String: AvailabilityDTO]
    /// Transfers in flight or finished this session.
    public var downloads: [DownloadDTO]
    /// Today's runs, as the canvas sidebar lists them.
    public var today: [RunSummary]
    /// How many pictures the library holds.
    public var libraryCount: Int
    /// Whether the Mac will take work right now, which is the one gate every command reads.
    public var acceptsWork: Bool

    /// Creates a snapshot.
    public init(
        protocolVersion: Int = LinkProtocolVersion.current,
        hostName: String,
        model: ModelSummary,
        models: [ModelSummary],
        engine: EngineStateDTO,
        queue: [QueuedEntry],
        running: QueuedEntry?,
        history: [HistoryEntry],
        availability: [String: AvailabilityDTO],
        downloads: [DownloadDTO],
        today: [RunSummary],
        libraryCount: Int,
        acceptsWork: Bool
    ) {
        self.protocolVersion = protocolVersion
        self.hostName = hostName
        self.model = model
        self.models = models
        self.engine = engine
        self.queue = queue
        self.running = running
        self.history = history
        self.availability = availability
        self.downloads = downloads
        self.today = today
        self.libraryCount = libraryCount
        self.acceptsWork = acceptsWork
    }
}
