import Foundation
import ZephraCore
import ZephraEngine
import ZephraLinkProtocol

/// The whole of the Mac's state, read off the store and the index at one instant.
///
/// Sent once when a session opens, and never again unless the phone asks: everything after it
/// is a `StateDelta`. It is read on the main actor in one go on purpose — a snapshot assembled
/// across suspensions could hold a queue from before a drain and a history from after it, which
/// is a state the Mac was never in.
@MainActor
public enum StateSnapshotProjection {
    /// What a session sends first.
    public static func snapshot(
        store: GenerationStore, index: LibraryIndex, hostName: String
    ) -> StateSnapshot {
        StateSnapshot(
            hostName: hostName,
            model: ModelSummary(store.descriptor),
            models: ModelCatalog.all.map(ModelSummary.init),
            engine: EngineStateDTO(store.state, modelID: store.descriptor.id),
            queue: QueuedEntryProjection.entries(store.queue),
            running: QueuedEntryProjection.running(store.running),
            history: HistoryEntryProjection.entries(store.history),
            availability: AvailabilityProjection.availability(store.availability),
            downloads: DownloadProjection.downloads(store.downloads.items),
            today: RunSummaryProjection.runs(
                items: index.items, history: store.history, queue: store.queue,
                running: store.running),
            libraryCount: LibraryEntryProjection.listing(index.items).count,
            acceptsWork: store.acceptsWork)
    }
}
