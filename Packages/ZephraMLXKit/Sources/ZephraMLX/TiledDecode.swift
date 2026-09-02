import Foundation
import MLX

/// Decodes a latent in overlapping tiles and blends where they meet.
///
/// An autoencoder's decode allocates in proportion to the image it is producing, not to its own
/// weights, which is why the peak of a generation is usually the decode rather than the model.
/// Taking tiles on a stride smaller than the tile, decoding each on its own, and cross-fading the
/// overlap bounds that peak by the tile size instead of by the image size. Each tile is evaluated
/// as it is produced, so only one tile's worth of feature maps is ever live.
///
/// Nothing here knows which autoencoder it is driving: it takes a latent, a tile edge, how many
/// pixels a latent cell becomes, and the untiled decode as a closure. The shape of the algorithm
/// is diffusers' `enable_vae_tiling`.
public nonisolated enum TiledDecode {
    /// `ZEPHRA_VAE_TILE` read as a latent-space tile edge, or nil when it is unset or too small
    /// to be worth the seams.
    ///
    /// One variable across every family, because a machine's decode budget is a property of the
    /// machine. A family reads this once for its own default and lets a host override it.
    public static let environmentTile: Int? = {
        guard let raw = ProcessInfo.processInfo.environment["ZEPHRA_VAE_TILE"],
            let value = Int(raw), value >= 16
        else { return nil }
        return value
    }()

    /// How much of a tile overlaps its neighbour. A quarter is diffusers' default and is enough
    /// for a stack of 3x3 convolutions to have forgotten the tile edge by the time it reaches
    /// the region that is kept.
    public static let overlapFactor = 0.25

    /// Decodes `latents` (NHWC) tile by tile.
    ///
    /// - Parameters:
    ///   - latents: the latent in NHWC, already denormalised, exactly as `decode` wants it.
    ///   - tile: tile edge in latent cells.
    ///   - scale: how many pixels one latent cell becomes along each edge.
    ///   - decode: the untiled decoder.
    /// - Returns: the decoded image, the same shape the untiled decode would have produced.
    public static func run(
        _ latents: MLXArray,
        tile: Int,
        scale: Int,
        decode: (MLXArray) -> MLXArray
    ) -> MLXArray {
        let height = latents.dim(1)
        let width = latents.dim(2)
        let stride = max(1, Int(Double(tile) * (1 - overlapFactor)))
        let blend = Int(Double(tile * scale) * overlapFactor)
        let keep = tile * scale - blend

        var rows: [[MLXArray]] = []
        for top in Swift.stride(from: 0, to: height, by: stride) {
            var row: [MLXArray] = []
            for left in Swift.stride(from: 0, to: width, by: stride) {
                let patch = latents[
                    0...,
                    top..<Swift.min(top + tile, height),
                    left..<Swift.min(left + tile, width),
                    0...
                ]
                let decoded = decode(patch)
                MLX.eval(decoded)
                row.append(decoded)
            }
            rows.append(row)
        }

        var joinedRows: [MLXArray] = []
        for (rowIndex, row) in rows.enumerated() {
            var pieces: [MLXArray] = []
            for (columnIndex, piece) in row.enumerated() {
                var blended = piece
                if rowIndex > 0 {
                    blended = crossFade(
                        rows[rowIndex - 1][columnIndex], blended, extent: blend, axis: 1)
                }
                if columnIndex > 0 {
                    blended = crossFade(row[columnIndex - 1], blended, extent: blend, axis: 2)
                }
                pieces.append(clipped(blended, to: keep))
            }
            joinedRows.append(MLX.concatenated(pieces, axis: 2))
        }
        return MLX.concatenated(joinedRows, axis: 1)
    }

    /// Replaces the first `extent` entries of `next` along `axis` with a linear ramp from the
    /// last `extent` entries of `previous` into them.
    private static func crossFade(
        _ previous: MLXArray, _ next: MLXArray, extent: Int, axis: Int
    ) -> MLXArray {
        let span = Swift.min(extent, previous.dim(axis), next.dim(axis))
        guard span > 0 else { return next }
        var rampShape = [1, 1, 1, 1]
        rampShape[axis] = span
        let weights = (0..<span).map { Float($0) / Float(span) }
        let ramp = MLXArray(weights, rampShape).asType(next.dtype)
        let inverse = MLXArray(weights.map { 1 - $0 }, rampShape).asType(next.dtype)

        let tail = slice(
            previous, axis: axis, from: previous.dim(axis) - span, to: previous.dim(axis))
        let head = slice(next, axis: axis, from: 0, to: span)
        let faded = tail * inverse + head * ramp
        let rest = slice(next, axis: axis, from: span, to: next.dim(axis))
        return rest.dim(axis) == 0 ? faded : MLX.concatenated([faded, rest], axis: axis)
    }

    /// The top-left `limit` by `limit` corner, or the whole thing when it is already smaller.
    private static func clipped(_ array: MLXArray, to limit: Int) -> MLXArray {
        array[
            0..., 0..<Swift.min(limit, array.dim(1)), 0..<Swift.min(limit, array.dim(2)), 0...]
    }

    private static func slice(_ array: MLXArray, axis: Int, from: Int, to: Int) -> MLXArray {
        axis == 1
            ? array[0..., from..<to, 0..., 0...]
            : array[0..., 0..., from..<to, 0...]
    }
}
