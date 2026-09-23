import Foundation

/// The size a picture is brought to: the output the pipeline picks from a reference's shape,
/// and the alignment both edges are trimmed to.
///
/// The reference's `calculate_dimensions` takes an area and an aspect and **rounds to the
/// nearest** multiple of 32, which is not the trim `__call__` then applies to a size handed in
/// — that one floors. Both are here, and they are different functions on purpose: rounding a
/// size somebody typed would silently grow it.
public enum QwenImage21ImageFitting {
    /// A size in pixels.
    public struct Target: Hashable, Sendable {
        /// Width in pixels.
        public let width: Int
        /// Height in pixels.
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    /// The pipeline's own `output_resolution` default; the area it aims for is its square.
    public static let outputResolution = 1024

    /// Both edges are trimmed to a multiple of this: `vae_scale_factor * 2` with a 16-times
    /// autoencoder.
    public static let alignment = 32

    /// `calculate_dimensions(target_area, ratio)`: the size covering about `area` pixels at
    /// `ratio` width to height, each edge **rounded** to the nearest multiple of `alignment`.
    ///
    /// The reference's `round` is Python's, which breaks a tie to even; Swift's
    /// `rounded(.toNearestOrEven)` is the same rule, and a half-way case is reachable at this
    /// alignment.
    public static func dimensions(
        targetArea: Int = outputResolution * outputResolution,
        ratio: Double,
        alignment: Int = alignment
    ) -> Target {
        let width = (Double(targetArea) * ratio).squareRoot()
        let height = width / ratio
        return Target(
            width: rounded(width, to: alignment),
            height: rounded(height, to: alignment))
    }

    /// The aspect of a `width` by `height` picture, for handing to `dimensions`.
    public static func ratio(width: Int, height: Int) -> Double {
        Double(width) / Double(height)
    }

    /// `width // multiple_of * multiple_of`: what `__call__` does to a size before it is used,
    /// never rounding up. Never below one cell, since a zero edge is not a picture.
    public static func trimmed(
        width: Int, height: Int, alignment: Int = alignment
    ) -> Target {
        Target(
            width: max(alignment, width / alignment * alignment),
            height: max(alignment, height / alignment * alignment))
    }

    private static func rounded(_ value: Double, to alignment: Int) -> Int {
        let steps = (value / Double(alignment)).rounded(.toNearestOrEven)
        return max(alignment, Int(steps) * alignment)
    }
}
