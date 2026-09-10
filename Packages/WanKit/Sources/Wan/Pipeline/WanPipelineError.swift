import Foundation

/// What can go wrong before a step runs.
public enum WanPipelineError: Error, LocalizedError, Equatable {
    /// `generate` was called with nothing loaded.
    case notLoaded
    /// A size the latent grid cannot hold: both edges must be multiples of `alignment`.
    case unalignedSize(width: Int, height: Int, alignment: Int)
    /// A frame count off the `1 + k * alignment` ladder.
    case unalignedFrames(frames: Int, alignment: Int)
    /// A first frame that CoreGraphics would not draw into a bitmap of the clip's size.
    case unreadableFirstFrame

    public var errorDescription: String? {
        switch self {
        case .notLoaded:
            "No model is loaded."
        case .unalignedSize(let width, let height, let alignment):
            "\(width) x \(height) is not a multiple of \(alignment) on both edges."
        case .unalignedFrames(let frames, let alignment):
            "\(frames) frames is not one more than a multiple of \(alignment)."
        case .unreadableFirstFrame:
            "The picture could not be drawn at the clip's size."
        }
    }
}
