import Foundation

/// The size a reference picture is brought to before the autoencoder sees it.
///
/// The reference pipeline scales a picture down until it covers at most a megapixel, keeping
/// its shape, and then trims each edge to the model's alignment — the autoencoder's reduction
/// times the packing, sixteen on the published model — so the latent grid comes out whole. The shape is kept on purpose: a reference squashed to the output's aspect would be
/// a different picture, and the transformer would faithfully edit that one instead.
public enum Flux2ImageFitting {
    /// A size in pixels.
    public struct Target: Hashable, Sendable {
        /// Width in pixels.
        public let width: Int
        /// Height in pixels.
        public let height: Int
    }

    /// The most pixels a reference is allowed to cover.
    public static let maximumArea = 1024 * 1024

    /// The size a `width` by `height` picture is fitted to, each edge a multiple of
    /// `alignment`, which is the loaded configuration's `sizeAlignment`.
    public static func target(width: Int, height: Int, alignment: Int) -> Target {
        let area = Double(width * height)
        let scale = min(1, (Double(maximumArea) / area).squareRoot())
        let scaledWidth = Int((Double(width) * scale).rounded(.down))
        let scaledHeight = Int((Double(height) * scale).rounded(.down))
        return Target(
            width: max(alignment, scaledWidth / alignment * alignment),
            height: max(alignment, scaledHeight / alignment * alignment))
    }
}
