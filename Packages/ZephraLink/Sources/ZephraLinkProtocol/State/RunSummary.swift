import Foundation
import ZephraEngine

/// One press of Generate, as the phone's sidebar draws it.
///
/// `TimelineRun` holds `TimelineTile`s, and a tile is either a `LibraryItem` or a whole
/// `GeneratedImage` with its PNG bytes in it. Neither crosses: what the phone needs from a run
/// is the file names, which it asks for as thumbnails when it draws them.
public struct RunSummary: Codable, Hashable, Sendable, Identifiable {
    /// Which state a run is in, which is what decides the row's shape.
    public enum State: String, Codable, Hashable, Sendable, CaseIterable {
        /// One of its seeds is being rendered right now.
        case running
        /// It is waiting its turn and nothing in it has started.
        case waiting
        /// Every seed it has is done.
        case finished
    }

    /// The run's identity: the `batchID` its seeds carry.
    public var id: UUID
    /// What it was asked to draw.
    public var prompt: String
    /// The model that ran it.
    public var modelID: String
    /// Pixels across.
    public var width: Int
    /// Pixels down.
    public var height: Int
    /// Where the run stands.
    public var state: State
    /// The file names of its finished pictures, oldest first. A poster for a clip.
    public var fileNames: [String]
    /// How many seeds it has in all: finished, queued and the one in flight.
    public var seedCount: Int
    /// When its first picture landed, or nil while it has none.
    public var startedAt: Date?
    /// When its last picture landed, or nil while it is not finished.
    public var finishedAt: Date?

    /// Creates a run row from explicit facts.
    public init(
        id: UUID, prompt: String, modelID: String, width: Int, height: Int, state: State,
        fileNames: [String], seedCount: Int, startedAt: Date?, finishedAt: Date?
    ) {
        self.id = id
        self.prompt = prompt
        self.modelID = modelID
        self.width = width
        self.height = height
        self.state = state
        self.fileNames = fileNames
        self.seedCount = seedCount
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
