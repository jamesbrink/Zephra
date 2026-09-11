import Foundation

/// A frame of the run in flight, on its way to the phone.
///
/// JPEG rather than the engine's RGBA8: a 256-pixel preview is a quarter of a megabyte raw and
/// a few kilobytes encoded, and these arrive several times a second over a link that may be a
/// relay on the far side of the world. `DTO` in the name because `ZephraCore.PreviewFrame` is
/// the protocol a kit's own frame conforms to, and two types under one name in one file would
/// read as the same thing.
public struct PreviewFrameDTO: Codable, Hashable, Sendable {
    /// The frame, JPEG encoded.
    public var jpeg: Data
    /// Pixels across.
    public var width: Int
    /// Pixels down.
    public var height: Int
    /// The step this frame came after, counting from one.
    public var step: Int
    /// How many steps the run has.
    public var steps: Int

    /// Creates a preview frame.
    public init(jpeg: Data, width: Int, height: Int, step: Int, steps: Int) {
        self.jpeg = jpeg
        self.width = width
        self.height = height
        self.step = step
        self.steps = steps
    }
}
