// ZEPHRA-PATCH: whole file. One frame of a generation still in flight, for a host that shows a
// run as it happens. Upstream has no such thing.
//
// The pooling and the byte packing are a copy of `ZephraMLX.LatentPreview`, which the other two
// families share. Vendored code is re-synced against upstream, and pointing it at one of our
// packages would put a Zephra dependency in this package's manifest and complicate every
// re-sync, which is the same reason `VAETiledDecode` is a copy of `ZephraMLX.TiledDecode`.
import Foundation
import MLX

/// One frame of a Z-Image generation still in flight: the run's estimate of the finished
/// latent, pooled and decoded small.
public struct ZImageLatentPreview: Sendable {
  /// Pixels across.
  public let width: Int
  /// Pixels down.
  public let height: Int
  /// `width * height * 4` bytes, RGBA8, row-major, opaque.
  public let pixels: Data

  /// The longest edge, in latent cells, a preview is pooled down to. Eight pixels a cell, so a
  /// frame is at most 256 pixels on its long edge and its decode about a sixteenth of the real
  /// one at 1024 pixels.
  static let cellLimit = 32

  /// Decodes one estimate of the finished latent.
  ///
  /// - Parameters:
  ///   - latents: `[1, 16, height, width]` NCHW. The loop passes its estimate of the finished
  ///     latent rather than the latent it holds; see the denoise loop for why.
  ///   - vae: the loaded model's, which is the only decoder that means anything here.
  public static func make(latents: MLXArray, vae: AutoencoderKL) -> ZImageLatentPreview {
    let factor = poolingFactor(height: latents.dim(2), width: latents.dim(3))
    let image = vae.decodeUntiled(pooled(latents, by: factor))
    MLX.eval(image)
    return ZImageLatentPreview(
      width: image.dim(2), height: image.dim(1), pixels: rgba8(image))
  }

  /// How much to pool a latent of this size by, so its long edge comes in under `cellLimit`.
  public static func poolingFactor(height: Int, width: Int) -> Int {
    let longest = Swift.max(height, width)
    guard longest > cellLimit else { return 1 }
    return (longest + cellLimit - 1) / cellLimit
  }

  /// Average-pools an NCHW latent by `factor` on both spatial axes, dropping the cells past the
  /// last whole block. Averaging rather than sampling: a latent is not smooth, and taking every
  /// fourth cell aliases into visible speckle where the mean of each block does not.
  public static func pooled(_ latents: MLXArray, by factor: Int) -> MLXArray {
    guard factor > 1 else { return latents }
    let (batch, channels) = (latents.dim(0), latents.dim(1))
    let height = (latents.dim(2) / factor) * factor
    let width = (latents.dim(3) / factor) * factor
    guard height > 0, width > 0 else { return latents }
    return MLX.mean(
      latents[0..., 0..., 0..<height, 0..<width]
        .reshaped([batch, channels, height / factor, factor, width / factor, factor]),
      axes: [3, 5])
  }

  /// One decoded frame, `[1, height, width, 3]` in the range -1 to 1, as opaque RGBA8 bytes.
  static func rgba8(_ image: MLXArray) -> Data {
    let frame = image[0]
    let (height, width) = (frame.dim(0), frame.dim(1))
    let scaled = MLX.clip(
      (frame + 1) * 127.5, min: MLXArray(Float(0)), max: MLXArray(Float(255)))
    let opaque = MLX.concatenated(
      [scaled, MLXArray.full([height, width, 1], values: MLXArray(Float(255)))], axis: -1)
    MLX.eval(opaque)
    return opaque.asType(.uint8).asData().data
  }
}
