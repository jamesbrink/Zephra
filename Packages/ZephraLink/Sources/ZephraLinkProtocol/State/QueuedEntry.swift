import Foundation
import ZephraCore
import ZephraEngine

/// One generation waiting its turn or being rendered, as a row.
///
/// It carries the run's whole settings, because the phone's capsule follows the Mac's run the
/// way the Mac's own capsule does (`PromptDraft.follow`): the prompt, the size, the schedule
/// and the seed of what the Mac is making are what a phone that walks in mid-run wants to
/// see. The settings are stripped of their pixels (`GenerationSettings.withoutPixels`) on the
/// way in and on the way out of the decoder, since the phone has no well for the Mac's picture
/// and a row is no place for megabytes of PNG. The queue on the phone is still a list to read
/// and to take things out of, not a list to edit: changing a queued entry's settings is not
/// something the Mac offers either.
public struct QueuedEntry: Codable, Hashable, Sendable, Identifiable {
    /// The entry's identity, which is what a removal names.
    public var id: UUID
    /// Which press of Generate produced it.
    public var batchID: UUID
    /// Where in that run it comes, counting from zero.
    public var batchIndex: Int
    /// The model it will run on.
    public var modelID: String
    /// Everything the run was asked for, with no picture in it.
    public private(set) var settings: GenerationSettings

    /// What it will draw.
    public var prompt: String { settings.prompt }
    /// Pixels across.
    public var width: Int { settings.size.width }
    /// Pixels down.
    public var height: Int { settings.size.height }
    /// The noise seed.
    public var seed: UInt64 { settings.seed }
    /// How many frames it makes; 1 is a picture.
    public var frames: Int { settings.frames }

    /// Creates a queue row from explicit facts, dropping any pixels the settings carry.
    public init(
        id: UUID, batchID: UUID, batchIndex: Int, modelID: String, settings: GenerationSettings
    ) {
        self.id = id
        self.batchID = batchID
        self.batchIndex = batchIndex
        self.modelID = modelID
        self.settings = settings.withoutPixels()
    }

    /// The wire form of one queued generation.
    public init(_ entry: QueuedGeneration) {
        self.init(
            id: entry.id, batchID: entry.batchID, batchIndex: entry.batchIndex,
            modelID: entry.model.id, settings: entry.settings)
    }

    /// Reads a row through the initializer, so pixels a peer put inside it are dropped too.
    /// Encoding stays synthesised over the same keys.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            batchID: try container.decode(UUID.self, forKey: .batchID),
            batchIndex: try container.decode(Int.self, forKey: .batchIndex),
            modelID: try container.decode(String.self, forKey: .modelID),
            settings: try container.decode(GenerationSettings.self, forKey: .settings))
    }

    private enum CodingKeys: String, CodingKey {
        case id, batchID, batchIndex, modelID, settings
    }
}
