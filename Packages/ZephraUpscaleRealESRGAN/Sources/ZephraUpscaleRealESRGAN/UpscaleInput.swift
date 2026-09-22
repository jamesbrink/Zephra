import Foundation
import MLX

/// A picture read for the upscaler: its colour, and its transparency where it has any.
///
/// Two tensors rather than one four-channel one because the network takes three channels and
/// the two lanes run through it separately — the colour as itself, the alpha as a grey triplet.
/// Keeping them apart here is what makes that obvious at the call site rather than a slice
/// somewhere inside it.
public struct UpscaleInput {
    /// `[1, height, width, 3]` float32 in 0...1: the picture's own colour, **straight**, with
    /// no matte multiplied into it.
    public let rgb: MLXArray
    /// `[1, height, width, 1]` float32 in 0...1, or nil for a picture with no alpha channel.
    public let alpha: MLXArray?

    /// Holds one read picture.
    public init(rgb: MLXArray, alpha: MLXArray?) {
        self.rgb = rgb
        self.alpha = alpha
    }

    /// The shape of the colour lane, which is the shape of the picture.
    public var shape: [Int] { rgb.shape }
}
