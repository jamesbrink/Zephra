import Foundation
import ZephraCore

/// What produced one image, written inside the PNG itself.
///
/// This is the whole of Zephra's history: no database, no sidecar file, no index. An image
/// carries its own provenance, so moving it, renaming it, or copying it to another Mac keeps
/// the record with it, and a folder of images is a complete library.
///
/// The fields are spelled out here rather than nesting `GenerationSettings`, so the on-disk
/// shape is this type's own business and renaming something in `ZephraCore` cannot silently
/// change what older files mean.
public struct GenerationRecord: Hashable, Sendable, Codable {
    /// The PNG text keyword the JSON is filed under.
    public static let keyword = "zephra:generation"
    /// The keyword the reference image is filed under, when the image was edited from one:
    /// the reference's own PNG bytes, base64, in a chunk of their own beside the record.
    public static let referenceKeyword = "zephra:reference"
    /// The shape written today. A file claiming a higher version is left alone rather than
    /// guessed at, so an older build never misreads a newer one's record.
    ///
    /// The version is for a change an older build would misread, not for a field it would
    /// simply not know: an optional field decodes as absent on an older file and is skipped by
    /// an older build, so adding one needs no bump.
    public static let currentVersion = 1

    /// Which shape this record is in.
    public var version: Int
    /// What the image was asked to show.
    public var prompt: String
    /// What it was asked to avoid, on models that read one.
    public var negativePrompt: String?
    /// Rendered width in pixels.
    public var width: Int
    /// Rendered height in pixels.
    public var height: Int
    /// How many denoising steps ran.
    public var steps: Int
    /// How strongly the prompt overrode the model's own priors.
    public var guidance: Double
    /// The noise seed, which is what makes the image reproducible.
    public var seed: UInt64
    /// The model that produced it, as a `ModelDescriptor` identifier.
    public var modelID: String
    /// When generation finished, to the second.
    public var createdAt: Date
    /// How long the whole generation took, in seconds.
    public var durationSeconds: Double
    /// How many bytes of PNG the reference image was, or nil when there was none.
    ///
    /// A count, not a flag: it puts "this was an edit" in the human-readable JSON that exiftool
    /// shows, and it is the check that the second chunk survived whatever tool last touched the
    /// file.
    public var referenceBytes: Int?

    /// The record for a finished image.
    public init(_ image: GeneratedImage) {
        version = Self.currentVersion
        prompt = image.settings.prompt
        negativePrompt = image.settings.negativePrompt
        width = image.settings.size.width
        height = image.settings.size.height
        steps = image.settings.steps
        guidance = image.settings.guidance
        seed = image.settings.seed
        modelID = image.modelID
        createdAt = image.createdAt
        durationSeconds = image.duration.seconds
        referenceBytes = image.settings.referenceImage?.count
    }

    /// The image this record describes, given the bytes it was read from and where they live.
    ///
    /// The identity is new every time: it is this session's handle on the file, not something
    /// the file carries. The model id is whatever produced the image, which need not be the
    /// model loaded now — selecting the image adopts its settings and leaves the model alone.
    public func image(
        pngData: Data, fileURL: URL?, referenceImage: Data? = nil
    ) -> GeneratedImage {
        GeneratedImage(
            pngData: pngData,
            settings: GenerationSettings(
                prompt: prompt,
                negativePrompt: negativePrompt,
                size: ImageSize(width: width, height: height),
                steps: steps,
                guidance: guidance,
                seed: seed,
                referenceImage: referenceImage
            ),
            modelID: modelID,
            createdAt: createdAt,
            duration: .seconds(durationSeconds),
            fileURL: fileURL
        )
    }
}
