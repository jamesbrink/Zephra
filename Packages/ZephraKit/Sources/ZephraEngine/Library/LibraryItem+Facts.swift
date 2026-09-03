import Foundation
import ZephraCore

/// The handful of things a grid cell, a sort, or an inspector row asks an item for, so none of
/// them has to know whether it is looking at a generated image or an imported picture.
extension LibraryItem {
    /// What the image was asked to show, or the empty string for an imported picture.
    public var prompt: String { provenance.record?.prompt ?? "" }

    /// The noise seed, or nil for anything Zephra did not make.
    public var seed: UInt64? { provenance.record?.seed }

    /// The model that produced it, as a `ModelDescriptor` identifier, or nil for an import.
    public var modelID: String? { provenance.record?.modelID }

    /// When the image was made, or when the picture was imported.
    public var createdAt: Date { provenance.createdAt }

    /// How long the generation took, or nil when that is not a question about this file.
    public var durationSeconds: Double? { provenance.record?.durationSeconds }

    /// The file's name on disk.
    public var fileName: String { url.lastPathComponent }

    /// The pixel dimensions, from whichever record the file carries.
    public var size: ImageSize {
        switch provenance {
        case .generated(let record): ImageSize(width: record.width, height: record.height)
        case .imported(let source): ImageSize(width: source.width, height: source.height)
        }
    }

    /// How many denoising steps ran, or nil for an imported picture.
    public var steps: Int? { provenance.record?.steps }

    /// The guidance the generation ran at, or nil for an imported picture.
    public var guidance: Double? { provenance.record?.guidance }

    /// Whether the image is marked as a favourite.
    public var isFavourite: Bool { annotation.isFavourite }

    /// The tags it carries.
    public var tags: [String] { annotation.tags }

    /// The picture this image was edited from, when it was, read from the file's own second
    /// chunk. Nil for an image made from noise, and nil rather than an error when the file has
    /// gone: a variation of a missing file is a request without a reference, not a failure.
    public var referenceImage: Data? {
        guard provenance.record?.referenceBytes != nil,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return GenerationRecord.reference(in: data)
    }
}
