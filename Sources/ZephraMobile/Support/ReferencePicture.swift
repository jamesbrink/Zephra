import Foundation
import ZephraCore

/// A picture on its way into the reference well: the PNG bytes that will cross the link, and
/// the shape they came out at.
///
/// The shape rides along because the size follows the picture on a model that makes clips
/// (`PromptDraft.adopt(_:origin:fitting:)`), and reading it back out of the bytes afterwards
/// would mean decoding the same picture twice.
struct ReferencePicture: Hashable, Sendable {
    /// The picture as PNG, at most `ReferenceImageEncoder.maximumPixelsPerEdge` an edge.
    let data: Data
    /// What those bytes are, in pixels.
    let size: ImageSize
}
