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
    /// The keyword the first reference image is filed under, when the image was edited from
    /// one: the reference's own PNG bytes, base64, in a chunk of their own beside the record.
    ///
    /// Pictures past the first are filed under this keyword suffixed with their 1-based
    /// position (`referenceKeyword(at:)`), so there is no `.1` to be confused with this one and
    /// every build that came before reads picture 1 exactly as it always did.
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
    /// How far from that picture the generation started, on a model that begins from a noised
    /// copy of it. Nil when there was no reference, and 1 on a model that conditions on the
    /// picture directly and so has no such distance to record.
    public var referenceStrength: Double?
    /// The library file name the reference picture came out of, when it came from the library,
    /// and nil when it came from a file chooser, a drop, or nowhere at all.
    ///
    /// A name rather than a path, for the reason the whole record is inside the PNG: a library
    /// that survives being moved to another Mac cannot hold absolute paths. Optional, so an
    /// older build reads a newer file as it always did and the version stays 1.
    public var referenceOrigin: String?
    /// How many bytes of PNG each reference picture was, the first included, on a generation
    /// that read more than one.
    ///
    /// Self-describing on purpose: the count of this list is how many numbered chunks the file
    /// carries, and each number is the length check for its own chunk, the way `referenceBytes`
    /// is for the first. Nil on a file written with one picture or none, where `referenceBytes`
    /// says everything there is to say. Optional, so an older build reads a newer file as it
    /// always did and the version stays 1.
    public var referenceByteCounts: [Int]?
    /// Where each of those pictures came from, positionally, nil for one that came from a file
    /// chooser or a drop. The first is `referenceOrigin` again, so the list is readable on its
    /// own. Optional, for the reason its neighbour is.
    public var referenceOrigins: [String?]?
    /// Which press of Generate produced the image, when it was one of several seeds, and nil
    /// otherwise.
    ///
    /// It is written so a run survives the session that made it: the timeline groups images by
    /// this, and a file read back after a relaunch would otherwise be a run of one. An optional
    /// field, so an older build reads a newer file as it always did and the version stays 1.
    public var batchID: UUID?
    /// The file name of the picture this one was made larger from, when it was an upscale, and
    /// nil when the pixels came out of a model.
    ///
    /// A name rather than a path, for the reason the whole record is inside the PNG: a library
    /// that survives being moved to another Mac cannot hold absolute paths. Optional, so an
    /// older build reads a newer file as it always did and the version stays 1.
    public var upscaledFrom: String?
    /// How many times larger each edge was made, when this was an upscale.
    public var upscaleFactor: Int?
    /// How many frames the clip has, when the picture is a clip's first frame; nil for a
    /// picture. The clip itself is the MP4 beside the file under the same stem
    /// (`VideoSidecar`), unnamed here because Put Back may rename both. Optional, so an older
    /// build reads a newer file as it always did and the version stays 1.
    public var frameCount: Int?
    /// Frames per second the clip plays at, when there is one.
    public var frameRate: Double?
    /// The library file name of the clip this one carries on from, when it was made by
    /// Extend Clip, and nil when it started from nothing or from a picture. The clip on disk
    /// is the source and the new segment joined; `frameCount` counts the whole. A name rather
    /// than a path, for the reason `upscaledFrom` is; optional, so the version stays 1.
    public var continuedFrom: String?
    /// How many of the source's last frames the model held to carry it on, when it did.
    public var contextFrames: Int?
    /// Whether the clip's MP4 carries sound, when the model made any; nil on a picture and on
    /// a clip written before models made sound. Optional, so the version stays 1.
    public var hasAudio: Bool?

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
        let pictures = image.settings.referenceImages.filter(\.hasPixels)
        referenceBytes = pictures.first?.data.count
        referenceStrength = pictures.isEmpty ? nil : image.settings.referenceStrength
        referenceOrigin = pictures.first?.origin
        // The two lists are written only where they say something the two scalars do not, so a
        // one-picture edit's record is byte for byte the record it has always been.
        referenceByteCounts = pictures.count > 1 ? pictures.map(\.data.count) : nil
        referenceOrigins = pictures.count > 1 ? pictures.map(\.origin) : nil
        batchID = image.batchID
        upscaledFrom = nil
        upscaleFactor = nil
        frameCount = image.video?.frameCount
        frameRate = image.video?.frameRate
        continuedFrom = image.settings.continuation?.origin
        contextFrames = image.settings.continuation?.contextFrames
        hasAudio = image.video.map(\.hasAudio)
    }

    /// Whether the picture is a clip's first frame.
    public var isVideo: Bool { (frameCount ?? 1) > 1 }
}
