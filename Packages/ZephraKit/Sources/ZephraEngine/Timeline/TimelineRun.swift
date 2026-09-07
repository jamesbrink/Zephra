import Foundation
import ZephraCore

/// One press of Generate, as the sidebar draws it: what was asked for, what has come out of it,
/// and what is still to come.
///
/// A run is the unit the timeline is made of, and it holds the same shape whether it is waiting,
/// running, or long finished — the tiles change, the row does not. That is what lets a card
/// become a plain row without anything moving.
public struct TimelineRun: Identifiable, Hashable, Sendable {
    /// The run's identity: the `batchID` every one of its seeds carries, or an id derived from
    /// its oldest image for a run assembled by adjacency out of files that carry none.
    public let id: UUID
    /// What the run was asked to draw.
    public let prompt: String
    /// The size every seed in it renders at.
    public let size: ImageSize
    /// The model that ran it, as a `ModelDescriptor` identifier.
    public let modelID: String
    /// Its finished images, oldest first. A seed still to come has no tile.
    public let tiles: [TimelineTile]
    /// Whether one of its seeds is being rendered right now. At most one run is.
    public let isRunning: Bool
    /// Whether the run is waiting its turn and nothing in it has started.
    public let isWaiting: Bool
    /// The queue entries still standing behind it, so a waiting run can be taken back out of
    /// the queue in one press rather than one seed at a time.
    public let queuedIDs: [QueuedGeneration.ID]

    /// Describes one run. Built by `SessionTimeline`; there is no other caller.
    public init(
        id: UUID,
        prompt: String,
        size: ImageSize,
        modelID: String,
        tiles: [TimelineTile],
        isRunning: Bool,
        isWaiting: Bool,
        queuedIDs: [QueuedGeneration.ID]
    ) {
        self.id = id
        self.prompt = prompt
        self.size = size
        self.modelID = modelID
        self.tiles = tiles
        self.isRunning = isRunning
        self.isWaiting = isWaiting
        self.queuedIDs = queuedIDs
    }

    /// How many of its seeds have produced an image, which is what the header counts.
    public var finishedCount: Int { tiles.count }

    /// How many seeds this run has in all: the finished ones, the ones still queued behind it,
    /// and the one being rendered right now, if any. What a waiting run's card counts, since it
    /// has no tiles of its own to count instead.
    public var seedCount: Int { tiles.count + queuedIDs.count + (isRunning ? 1 : 0) }
}
