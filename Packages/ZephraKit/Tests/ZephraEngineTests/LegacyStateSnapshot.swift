// Frozen outer wire decoder from pre-multi-host 95ede16. Nested DTOs are shared.
import Foundation
import ZephraLinkProtocol

/// The whole of the Mac's state, sent once when a session opens.
///
/// One message rather than a dozen, because a phone with half a state cannot draw anything: the
/// snapshot is what makes the first frame correct, and every `LegacyStateDelta` after it is an edit
/// to this. A phone that misses a delta asks for a snapshot again rather than reconciling.
struct LegacyStateSnapshot: Codable, Hashable, Sendable {
    /// Which protocol this Mac speaks, repeated here so a snapshot read from a log says.
    var protocolVersion: Int
    /// What the Mac is called, as it appears on the phone's list of Macs.
    var hostName: String
    /// The model in force.
    var model: ModelSummary
    /// Every model the catalog holds, in the order the Mac lists them.
    var models: [ModelSummary]
    /// Where the engine is.
    var engine: EngineStateDTO
    /// What is waiting, in order.
    var queue: [QueuedEntry]
    /// What is being rendered, or nil.
    var running: QueuedEntry?
    /// What this session has finished, newest first.
    var history: [HistoryEntry]
    /// Whether each model's weights are here, keyed by descriptor identifier.
    var availability: [String: AvailabilityDTO]
    /// Transfers in flight or finished this session.
    var downloads: [DownloadDTO]
    /// Today's runs, as the canvas sidebar lists them.
    var today: [RunSummary]
    /// How many pictures the library holds.
    var libraryCount: Int
    /// Whether the Mac will take work right now, which is the one gate every command reads.
    var acceptsWork: Bool

    /// Creates a snapshot.
    init(
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
