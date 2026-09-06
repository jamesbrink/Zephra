import Foundation
import ZephraCore

/// The record read back as a request.
extension GenerationRecord {
    /// What the record asks for, as a request that could be run again.
    ///
    /// The one place the flat on-disk fields become a `GenerationSettings`, so opening an image
    /// and queueing a variation of it read the record the same way. The picture an edit started
    /// from is a separate chunk rather than a field, so it is passed in by whoever read the
    /// file: `GenerationRecord.reference(in:)` answers for the bytes in hand.
    ///
    /// The strength comes back with it, defaulting to 1 — no reference, or a model that never
    /// had a distance to travel — so a variation of an edit repeats the edit rather than
    /// quietly becoming a stronger one.
    public func settings(referenceImage: Data? = nil) -> GenerationSettings {
        GenerationSettings(
            prompt: prompt,
            negativePrompt: negativePrompt,
            size: ImageSize(width: width, height: height),
            steps: steps,
            guidance: guidance,
            seed: seed,
            referenceImage: referenceImage,
            referenceStrength: referenceStrength ?? 1,
            frames: frameCount ?? 1
        )
    }
}
