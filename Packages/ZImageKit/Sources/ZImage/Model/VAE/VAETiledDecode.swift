import Foundation
import MLX

// ZEPHRA-PATCH: (new file) opt-in tiled VAE decode. The decode's transient is set by the
// resolution it runs at, not by the weights, so decoding overlapping latent tiles and blending
// the seams bounds peak memory by the tile size instead of by the image size. Off by default;
// ZEPHRA_VAE_TILE names the latent-space tile edge (64 decodes in 512-pixel tiles) and is the
// starting value of `latentTile`, which a host can also set at runtime.
/// Decodes a latent in overlapping tiles and blends where they meet.
///
/// The shape of the algorithm is diffusers' `enable_vae_tiling`: tiles are taken on a stride
/// smaller than the tile, each is decoded on its own, and the overlap is cross-faded with a
/// linear ramp so no seam appears. Each tile is evaluated as it is produced, so only one tile's
/// worth of intermediate feature maps is ever live.
public enum VAETiledDecode {
  /// Latent-space tile edge in force, or nil when the decode runs untiled and exact.
  ///
  /// Starts from `ZEPHRA_VAE_TILE` so the benchmark and the command line keep working, and is
  /// settable so a host can decide per model without a relaunch. Written from the UI and read
  /// on the inference thread; a torn read cannot happen for a word-sized optional, and the worst
  /// a race can do is decode one image with the previous setting.
  public nonisolated(unsafe) static var latentTile: Int? = environmentTile

  /// `ZEPHRA_VAE_TILE` read as a tile edge, or nil when it is unset or too small to be useful.
  static let environmentTile: Int? = {
    guard let raw = ProcessInfo.processInfo.environment["ZEPHRA_VAE_TILE"],
      let value = Int(raw), value >= 16
    else { return nil }
    return value
  }()

  /// How much of a tile overlaps its neighbour. A quarter is diffusers' default and is enough
  /// for a 3x3 convolution stack to have forgotten the tile edge by the time it reaches the
  /// kept region.
  static let overlapFactor = 0.25

  /// Decodes `latents` (NHWC) tile by tile, calling `body` for each tile.
  ///
  /// - Parameters:
  ///   - latents: the latent, already in NHWC and already scaled and shifted.
  ///   - tile: tile edge in latent space.
  ///   - scale: how many pixels one latent cell becomes along each edge.
  ///   - body: the untiled decoder. It may throw, which is how a caller stops between tiles:
  ///     a 1024-pixel decode is seconds, and Stop should not wait for it.
  static func decode(
    _ latents: MLXArray,
    tile: Int,
    scale: Int,
    body: (MLXArray) throws -> MLXArray  // ZEPHRA-PATCH: stop between VAE tiles
  ) rethrows -> MLXArray {  // ZEPHRA-PATCH: stop between VAE tiles
    let height = latents.dim(1)
    let width = latents.dim(2)
    // Stride is rounded once, in latent cells, and the pixel counts follow from it: a tile
    // whose quarter is not whole would otherwise keep more pixels than it strides past, and
    // the output would come back wider than the image with a doubled band at every seam.
    let stride = max(1, Int(Double(tile) * (1 - overlapFactor)))
    let blend = (tile - stride) * scale
    let keep = stride * scale

    var rows: [[MLXArray]] = []
    for top in Swift.stride(from: 0, to: height, by: stride) {
      var row: [MLXArray] = []
      for left in Swift.stride(from: 0, to: width, by: stride) {
        let patch = latents[
          0..., top ..< Swift.min(top + tile, height), left ..< Swift.min(left + tile, width), 0...]
        let decoded = try body(patch)  // ZEPHRA-PATCH: stop between VAE tiles
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
          blended = crossFade(rows[rowIndex - 1][columnIndex], blended, extent: blend, axis: 1)
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
    let weights = (0 ..< span).map { Float($0) / Float(span) }
    let ramp = MLXArray(weights, rampShape).asType(next.dtype)
    let inverse = MLXArray(weights.map { 1 - $0 }, rampShape).asType(next.dtype)

    let tail = slice(previous, axis: axis, from: previous.dim(axis) - span, to: previous.dim(axis))
    let head = slice(next, axis: axis, from: 0, to: span)
    let faded = tail * inverse + head * ramp
    let rest = slice(next, axis: axis, from: span, to: next.dim(axis))
    return rest.dim(axis) == 0 ? faded : MLX.concatenated([faded, rest], axis: axis)
  }

  /// The top-left `limit` by `limit` corner, or the whole thing when it is already smaller.
  private static func clipped(_ array: MLXArray, to limit: Int) -> MLXArray {
    array[0..., 0 ..< Swift.min(limit, array.dim(1)), 0 ..< Swift.min(limit, array.dim(2)), 0...]
  }

  private static func slice(_ array: MLXArray, axis: Int, from: Int, to: Int) -> MLXArray {
    axis == 1
      ? array[0..., from ..< to, 0..., 0...]
      : array[0..., 0..., from ..< to, 0...]
  }
}
