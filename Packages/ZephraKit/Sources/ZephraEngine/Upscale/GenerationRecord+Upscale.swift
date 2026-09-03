import Foundation
import ZephraCore

/// The provenance of a picture that was made larger rather than made.
///
/// Pure arithmetic over one record, no file system and no engine: what an upscale keeps from
/// its parent, what it replaces, and what it says about itself. That is the whole of the rule,
/// so it is the whole of this file and it is pinned by its own tests.
extension GenerationRecord {
    /// The record for the result of upscaling `parent` by `factor`.
    ///
    /// With a parent record everything about how the pixels were made is carried across —
    /// prompt, negative prompt, steps, guidance, seed, model, and the reference it was edited
    /// from — because it is all still true of them. What changes is what the file is: the new
    /// size, the moment it was written, how long the upscale took, no batch (an upscale is one
    /// picture, not one of several seeds), and the two fields that say where it came from.
    ///
    /// Without one — the parent is an imported photograph, or a PNG some other tool made — the
    /// result still gets a record, so the library lists it: an empty prompt, no steps, no
    /// guidance and no seed, and the upscaler itself as the model. Those zeroes are what
    /// `ImageFacts` shows as em dashes rather than as numbers that were never true.
    public static func upscaled(
        from parent: GenerationRecord?,
        parentFileName: String,
        factor: Int,
        size: ImageSize,
        duration: Duration
    ) -> GenerationRecord {
        var record = parent ?? imported(factor: factor)
        record.version = currentVersion
        record.width = size.width
        record.height = size.height
        record.createdAt = Date()
        record.durationSeconds = duration.seconds
        record.batchID = nil
        record.upscaledFrom = parentFileName
        record.upscaleFactor = factor
        return record
    }

    /// The bare record an upscale of a picture Zephra did not make starts from.
    private static func imported(factor: Int) -> GenerationRecord {
        GenerationRecord(
            GeneratedImage(
                pngData: Data(),
                settings: GenerationSettings(
                    prompt: "", size: ImageSize(width: 0, height: 0), steps: 0, guidance: 0,
                    seed: 0),
                modelID: "real-esrgan-x\(factor)",
                duration: .zero))
    }
}
