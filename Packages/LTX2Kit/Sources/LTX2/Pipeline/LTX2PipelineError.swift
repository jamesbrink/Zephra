import Foundation

/// What a request can get wrong before a weight is touched.
public enum LTX2PipelineError: Error, Equatable, Sendable {
    /// `generate` was called with nothing loaded.
    case notLoaded
    /// A width or height that is not a multiple of the autoencoder's 32-pixel cell.
    case unalignedSize(width: Int, height: Int, alignment: Int)
    /// A frame count that is not `1 + 8k`, which the autoencoder cannot make.
    case unalignedFrames(frames: Int, alignment: Int)
}
