// Frozen outer wire decoder from pre-multi-host 95ede16. Nested DTOs are shared.
import Foundation
import ZephraLinkProtocol

/// One change to the state the phone is holding.
///
/// One change each, never a bundle. The Mac publishes what moved as it moves, and a phone that
/// applies them in order ends where the Mac is; a delta carrying two changes would be a small
/// transaction format, and the first thing anyone would want is a third.
enum LegacyStateDelta: Hashable, Sendable {
    /// The engine moved.
    case engine(EngineStateDTO)
    /// The queue is now this.
    case queue([QueuedEntry])
    /// This is being rendered, or nothing is.
    case running(QueuedEntry?)
    /// A picture landed.
    case historyInserted(HistoryEntry)
    /// A picture left this session's history.
    case historyRemoved(UUID)
    /// The model in force changed.
    case model(ModelSummary)
    /// Availability was surveyed again.
    case availability([String: AvailabilityDTO])
    /// The transfers are now these.
    case downloads([DownloadDTO])
    /// Today's runs are now these.
    case today([RunSummary])
    /// The library changed.
    case library(LibraryChange)
    /// The Mac started or stopped taking work.
    case acceptsWork(Bool)
}
