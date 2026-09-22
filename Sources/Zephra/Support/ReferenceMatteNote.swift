import Foundation
import ZephraCore
import ZephraEngine

/// Whether the well owes a line about transparency, and what that line says.
///
/// Every reference path but one draws the picture into an opaque bitmap before it encodes it, so
/// a cut-out handed to any model that does not declare
/// `ModelCapabilities.readsTransparentReferences` arrives over white. That is a fact worth
/// saying where the picture is, rather than one to be discovered in the result: the well draws
/// the checkerboard behind a transparent reference, which reads as a promise this model cannot
/// keep, and the note is what keeps the two honest with each other.
///
/// The file's own header answers whether a picture is transparent, never a record field — the
/// rule `ImageFacts.isTransparent` already follows — and here the header is the PNG in hand, so
/// no file is read at all. `nonisolated`, because reading ten of them belongs off the main actor.
enum ReferenceMatteNote {
    /// The line to show under the well, or nil when there is nothing to say: no pictures, a
    /// model that reads no picture at all, a model that reads the transparency itself, or
    /// pictures that carry none.
    nonisolated static func text(
        for pictures: [ReferencePicture], capabilities: ModelCapabilities, modelName: String
    ) -> String? {
        guard capabilities.supportsReferenceImage, !capabilities.readsTransparentReferences,
              !pictures.isEmpty
        else { return nil }
        guard pictures.contains(where: isTransparent) else { return nil }
        return ReferenceRole(capabilities: capabilities).whiteMatteNote(modelName: modelName)
    }

    /// Whether one picture carries alpha, by its own header. Bytes that are not a PNG at all —
    /// which nothing in the well should be, since every door encodes one — answer no rather
    /// than throwing a note onto the screen about a picture nobody can see.
    nonisolated static func isTransparent(_ picture: ReferencePicture) -> Bool {
        guard picture.hasPixels else { return false }
        return ((try? PNGHeader.read(from: picture.data))?.hasAlpha) ?? false
    }
}
