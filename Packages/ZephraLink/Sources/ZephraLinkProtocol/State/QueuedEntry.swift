import Foundation
import ZephraEngine

/// One generation waiting its turn, as a row.
///
/// The settings are flattened to the few the row shows. The queue on the phone is a list to
/// read and to take things out of, not a list to edit: changing a queued entry's settings is
/// not something the Mac offers either.
public struct QueuedEntry: Codable, Hashable, Sendable, Identifiable {
    /// The entry's identity, which is what a removal names.
    public var id: UUID
    /// Which press of Generate produced it.
    public var batchID: UUID
    /// Where in that run it comes, counting from zero.
    public var batchIndex: Int
    /// The model it will run on.
    public var modelID: String
    /// What it will draw.
    public var prompt: String
    /// Pixels across.
    public var width: Int
    /// Pixels down.
    public var height: Int
    /// The noise seed.
    public var seed: UInt64
    /// How many frames it makes; 1 is a picture.
    public var frames: Int

    /// Creates a queue row from explicit facts.
    public init(
        id: UUID, batchID: UUID, batchIndex: Int, modelID: String, prompt: String,
        width: Int, height: Int, seed: UInt64, frames: Int
    ) {
        self.id = id
        self.batchID = batchID
        self.batchIndex = batchIndex
        self.modelID = modelID
        self.prompt = prompt
        self.width = width
        self.height = height
        self.seed = seed
        self.frames = frames
    }

    /// The wire form of one queued generation.
    public init(_ entry: QueuedGeneration) {
        self.init(
            id: entry.id, batchID: entry.batchID, batchIndex: entry.batchIndex,
            modelID: entry.model.id, prompt: entry.settings.prompt,
            width: entry.settings.size.width, height: entry.settings.size.height,
            seed: entry.settings.seed, frames: entry.settings.frames)
    }
}
