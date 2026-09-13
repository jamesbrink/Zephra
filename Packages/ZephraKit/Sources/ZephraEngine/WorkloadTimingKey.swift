import Foundation
import ZephraCore

/// Only comparable work shares a passive sample. No prompts, pixels or seeds are retained.
public struct WorkloadTimingKey: Hashable, Sendable {
    public let modelID: String
    public let revision: String
    public let residency: String
    public let width: Int
    public let height: Int
    public let steps: Int
    public let frames: Int
    public let reference: Bool
    public let strength: Double
    public let continuation: Bool
    public let tiled: Bool

    public init(modelID: String, revision: String, residency: WeightResidency,
                settings: GenerationSettings, tiled: Bool) {
        self.modelID = modelID; self.revision = revision; self.residency = residency.rawValue
        width = settings.size.width; height = settings.size.height
        steps = settings.steps; frames = settings.frames
        reference = settings.referenceImage != nil
        strength = reference ? settings.referenceStrength : 1
        continuation = settings.continuation != nil; self.tiled = tiled
    }
}
