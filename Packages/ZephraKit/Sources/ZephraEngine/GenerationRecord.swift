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
    /// The shape written today. A file claiming a higher version is left alone rather than
    /// guessed at, so an older build never misreads a newer one's record.
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
    /// The file name of the picture this generation started from, when it started from one.
    ///
    /// A name, not a path: the library moves between Macs and home directories, and the
    /// sources folder is found relative to the image rather than remembered absolutely.
    public var referenceFileName: String?
    /// The SHA-256 of that file's bytes at the time, lowercase hex.
    ///
    /// The name says which file; this says which *version* of it. A source replaced in place
    /// under the same name no longer matches, and the inspector can say so instead of
    /// claiming a provenance that is no longer true.
    public var referenceDigest: String?
    /// How far the generation was allowed to travel from that picture. See `ReferenceImage`.
    public var referenceStrength: Double?

    /// The record for a finished image, taking the reference's provenance from the caller.
    ///
    /// The digest is passed in rather than computed here, because hashing the source file is
    /// I/O and this initializer is called on whatever actor finished the generation. The store
    /// computes it once, off the main actor, as it saves.
    public init(_ image: GeneratedImage, referenceDigest: String?) {
        self.init(image)
        self.referenceDigest = referenceDigest
    }

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
        referenceFileName = image.settings.reference?.url.lastPathComponent
        referenceStrength = image.settings.reference?.strength
    }

    /// The image this record describes, given the bytes it was read from and where they live.
    ///
    /// The identity is new every time: it is this session's handle on the file, not something
    /// the file carries. The model id is whatever produced the image, which need not be the
    /// model loaded now — selecting the image adopts its settings and leaves the model alone.
    ///
    /// A reference comes back only when `fileURL` says where the image is, because the source
    /// file is found relative to it — see `reference(nextTo:)`.
    public func image(pngData: Data, fileURL: URL?) -> GeneratedImage {
        GeneratedImage(
            pngData: pngData,
            settings: GenerationSettings(
                prompt: prompt,
                negativePrompt: negativePrompt,
                size: ImageSize(width: width, height: height),
                steps: steps,
                guidance: guidance,
                seed: seed,
                reference: fileURL.flatMap(reference(nextTo:))
            ),
            modelID: modelID,
            createdAt: createdAt,
            duration: .seconds(durationSeconds),
            fileURL: fileURL
        )
    }
}
