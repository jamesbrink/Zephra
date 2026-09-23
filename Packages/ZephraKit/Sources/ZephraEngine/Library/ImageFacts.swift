import Foundation
import ZephraCore

/// The lines the inspector shows about one image, already formatted.
///
/// Formatting here rather than in the view because the same seven lines describe an image on the
/// canvas and an image in the library, and because "how long it took" has enough rules — no
/// answer at all, seconds, minutes, a per-step figure — to be worth testing.
public struct ImageFacts: Hashable, Sendable {
    /// The model that made it, by name when the catalog knows it.
    public let model: String
    /// Pixel dimensions.
    public let size: String
    /// How many denoising steps ran.
    public let steps: String
    /// The seed, spelled the way the `SeedFormat` it was built with spells seeds.
    public let seed: String
    /// How long it took, and what that was per step.
    public let took: String
    /// The file's name on disk.
    public let file: String
    /// What it was made larger from, and by how much, or nil when it was not an upscale.
    public let upscaled: String?
    /// How long the clip runs and how many frames it has, or nil for a picture.
    public let length: String?
    /// The clip this one carries on from and how many of its frames were held, or nil when
    /// the clip was not made by Extend Clip.
    public let continued: String?
    /// How far from the reference picture the generation started, to two decimals, or nil when
    /// there was no picture and when the strength was 1 — a model that conditions on the
    /// picture directly had no distance to travel, and a row saying "1.00" says nothing.
    public let referenceStrength: String?
    /// The same number unformatted, for an interface that words some value of it specially:
    /// LTX-2.5 runs the scale the other way and its 0 means the first frame is held exactly,
    /// which reads as a phrase rather than as a number. `length` says which kind of picture
    /// this is, so the caller has both halves of that question.
    public let referenceStrengthValue: Double?
    /// The library file the first reference picture came out of, or nil when it came from a
    /// file chooser, a drop, or nowhere at all.
    public let referenceOrigin: String?
    /// Where each of the pictures came from, positionally, nil for one that came from a file
    /// chooser or a drop. Empty where there was no picture; one entry where there was one, so
    /// a single-picture inspector may read either this or `referenceOrigin`.
    public let referenceOrigins: [String?]
    /// How many pictures the generation read, which is what an inspector counts its rows by.
    public let referenceCount: Int
    /// Whether the picture carries transparency, read from the file's own header rather than
    /// from anything in the record: an imported picture and one Zephra made answer the same
    /// way, and a record written before there was a model that makes transparency would not.
    /// The inspector draws the line only when it is true, the rule `referenceStrength`
    /// already follows — a row saying "No" says nothing.
    public let isTransparent: Bool

    /// The facts about a library image. `modelName` is the catalog's name for it, when there is
    /// one; without it the identifier written into the file is shown, which is the honest answer
    /// for an image made by a model this build no longer carries. `seedFormat` is the
    /// preference the inspector reads; the short label unless the interface says otherwise.
    public init(_ item: LibraryItem, modelName: String? = nil, seedFormat: SeedFormat = .hex) {
        model = modelName ?? item.modelID ?? Self.unknown
        size = Self.label(item.size)
        steps = Self.stepsLabel(item.steps)
        seed = Self.seedLabel(item.seed, as: seedFormat)
        // An upscale's seconds are the network's, not the steps', so the per-step figure that
        // would follow from the parent's step count is left off.
        took = Self.tookLabel(
            seconds: item.durationSeconds ?? 0, steps: item.upscale == nil ? item.steps ?? 0 : 0)
        file = item.fileName
        upscaled = item.upscale.map { "\u{00D7}\($0.factor) from \($0.parent)" }
        length = item.provenance.record.flatMap { record in
            record.frameCount.map {
                Self.lengthLabel(frames: $0, rate: record.frameRate ?? 24, sound: record.hasAudio ?? false)
            }
        }
        continued = item.provenance.record.flatMap { record in
            record.continuedFrom.map { Self.continuedLabel(from: $0, held: record.contextFrames ?? 0) }
        }
        // The record's own strength is already nil where there was no picture.
        referenceStrengthValue = Self.reportable(item.provenance.record?.referenceStrength)
        referenceStrength = referenceStrengthValue.map(Self.strengthLabel)
        referenceOrigin = item.provenance.record?.referenceOrigin
        // The record's own lists where it has them, and the two scalars where it has not: a
        // file written with one picture says everything it has to say in those.
        let record = item.provenance.record
        referenceOrigins = record?.referenceOrigins
            ?? (record?.referenceBytes == nil ? [] : [record?.referenceOrigin])
        referenceCount = record?.referenceByteCounts?.count
            ?? (record?.referenceBytes == nil ? 0 : 1)
        isTransparent = item.hasAlpha
    }

    /// The facts about an image in memory, which may not have reached the disk yet.
    public init(_ image: GeneratedImage, modelName: String? = nil, seedFormat: SeedFormat = .hex) {
        model = modelName ?? image.modelID
        size = Self.label(image.settings.size)
        steps = Self.stepsLabel(image.settings.steps)
        seed = Self.seedLabel(image.settings.seed, as: seedFormat)
        took = Self.tookLabel(seconds: image.duration.seconds, steps: image.settings.steps)
        file = image.fileURL?.lastPathComponent ?? Self.notSaved
        // A picture in memory has no record to read it from, and the library's own inspector
        // takes over the moment the scan lands, which is typically inside a second.
        upscaled = nil
        length = image.video.map { Self.lengthLabel(frames: $0.frameCount, rate: $0.frameRate, sound: $0.hasAudio) }
        continued = image.settings.continuation.flatMap { continuation in
            continuation.origin.map { Self.continuedLabel(from: $0, held: continuation.contextFrames) }
        }
        let settings = image.settings
        referenceStrengthValue = settings.referenceImage == nil
            ? nil : Self.reportable(settings.referenceStrength)
        referenceStrength = referenceStrengthValue.map(Self.strengthLabel)
        let pictures = settings.referenceImages.filter(\.hasPixels)
        referenceOrigin = pictures.first?.origin
        referenceOrigins = pictures.map(\.origin)
        referenceCount = pictures.count
        // A picture in memory has no file to ask, so its own bytes answer: the same walk the
        // scan makes, over the header of the PNG the backend handed back.
        isTransparent = (try? PNGHeader.read(from: image.pngData).hasAlpha) ?? false
    }
}
