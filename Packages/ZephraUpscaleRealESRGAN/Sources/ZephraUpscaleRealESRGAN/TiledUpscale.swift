import Foundation
import MLX
import ZephraCore
import ZephraMLX

/// Running the network over a picture in overlapping tiles, reporting each one and stopping
/// between them.
///
/// A 4x pass allocates in proportion to the picture it is producing, so an untiled 2048-pixel
/// input would ask for an 8192-pixel feature map. `TiledDecode` is already the answer to that
/// question for the autoencoders, and it is generic over any NHWC closure and an integer scale,
/// so it is the answer here too.
///
/// The tile is 512 input pixels, which strides 384 and overlaps 128. The network's receptive
/// field is 34 pixels each side — 33 padded 3x3 convolutions before the shuffle — so a 128-pixel
/// overlap is 3.7 times it, and a tile's kept region is untouched by its own zero padding except
/// for a 34-pixel sliver at the low end of the fade, where the incoming tile's weight runs from
/// 0 to 0.27. That bound is what `TilingTests` asserts against, and it is why the claim is a
/// tolerance rather than equality.
public enum TiledUpscale {
    /// The tile edge, in input pixels.
    public static let tile = 512

    /// How many tiles a `height` by `width` picture is cut into.
    public static func tileCount(height: Int, width: Int) -> Int {
        TiledDecode.tileCount(height: height, width: width, tile: tile)
    }

    /// Enlarges `pixels`, NHWC in 0...1, by `network`'s scale, tile by tile.
    ///
    /// Cancellation is checked at the top of every tile and reported as
    /// `UpscaleError.cancelled` rather than as `CancellationError`: the seam has a case for it,
    /// and an upscale that stops has one story whether the task was cancelled or the tiler gave
    /// up. `TiledDecode.run` is `rethrows`, so the throw unwinds the whole run and the tiles
    /// already held are released.
    ///
    /// - Parameter onTile: called after each tile with how many are done and how many there are.
    public static func run(
        _ pixels: MLXArray,
        through network: SRVGGNet,
        onTile: ((Int, Int) -> Void)? = nil
    ) throws -> MLXArray {
        try TiledDecode.run(
            pixels, tile: tile, scale: network.configuration.scale, onTile: onTile
        ) { patch in
            guard !Task.isCancelled else { throw UpscaleError.cancelled }
            return network(patch)
        }
    }
}
