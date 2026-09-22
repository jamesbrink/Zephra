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
    /// quietly becoming a stronger one. The origin comes back beside it, so a variation of an
    /// edit still says which library picture it started from.
    public func settings(referenceImage: Data? = nil) -> GenerationSettings {
        // An origin names a picture's source; without the picture there is nothing it is of,
        // which is what building the one picture from both fields together gives for free.
        settings(referenceImages: referenceImage.map {
            [ReferencePicture(data: $0, origin: referenceOrigin)]
        } ?? [])
    }

    /// The same, for a caller holding every picture the record's numbered chunks carried
    /// (`GenerationRecord.references(in:)`), which is what a variation of a several-picture edit
    /// repeats.
    public func settings(referenceImages: [ReferencePicture]) -> GenerationSettings {
        GenerationSettings(
            prompt: prompt,
            negativePrompt: negativePrompt,
            size: ImageSize(width: width, height: height),
            steps: steps,
            guidance: guidance,
            seed: seed,
            referenceImages: referenceImages,
            referenceStrength: referenceStrength ?? 1,
            frames: frameCount ?? 1
        )
    }
}
