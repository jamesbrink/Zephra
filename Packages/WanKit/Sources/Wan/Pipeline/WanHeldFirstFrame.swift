import Foundation
import MLX

/// A picture encoded to the clip's first latent frame, with the mask that says which cells
/// hold it.
///
/// The encoder is causal in time, so one picture encodes to exactly one latent frame; the
/// mask is `[1, 1, frames, height, width]`, 0 over that frame and 1 everywhere else, which is
/// what the reference's image-to-video pipeline builds (`first_frame_mask`) and reads at three
/// places: the model's input, the per-token timestep, and the finished latent.
struct WanHeldFirstFrame {
    /// The picture's latent, `[1, 48, 1, height, width]`, in the transformer's normalised space.
    let latent: MLXArray
    /// 0 where the picture is held, 1 where the clip is made.
    let mask: MLXArray
    /// The layout the mask was built for.
    let layout: WanLatentLayout

    /// Encodes `frame`'s picture at the clip's size, one pixel frame the causal encoder turns
    /// into exactly one latent frame, and normalises it into the transformer's space.
    init(_ frame: WanFirstFrame, layout: WanLatentLayout, with loaded: WanPipeline.Loaded) throws {
        let pixels = try WanFirstFramePixels.pixels(
            from: frame.image,
            width: layout.width * WanLatentLayout.cellScale,
            height: layout.height * WanLatentLayout.cellScale)
        let encoded = loaded.autoencoder.encode(pixels.asType(loaded.autoencoder.dtype))
        self.init(latent: loaded.normalization.normalize(encoded.asType(.float32)), layout: layout)
    }

    /// A latent frame already in the transformer's space, for the tests.
    init(latent: MLXArray, layout: WanLatentLayout) {
        self.latent = latent
        self.layout = layout
        var mask = MLXArray.ones([1, 1, layout.frames, layout.height, layout.width])
        mask[0..., 0..., 0..<1] = MLXArray.zeros([1, 1, 1, layout.height, layout.width])
        self.mask = mask
    }

    /// `sample` with the picture put in over its first frame: what the transformer reads.
    func imposed(on sample: MLXArray) -> MLXArray {
        let clean = MLX.concatenated(
            [latent, MLXArray.zeros([1, latent.dim(1), layout.frames - 1, layout.height, layout.width])],
            axis: 2)
        return clean * (1 - mask) + sample * mask
    }

    /// The timestep of every token at step `timestep`: 0 over the held frame's tokens and
    /// `timestep` elsewhere, `[1, tokens]`, in the transformer's patch order — the mask
    /// sampled at every other cell, as the reference's `first_frame_mask[0][0][:, ::2, ::2]`.
    func timesteps(_ timestep: Double) -> MLXArray {
        let patch = WanLatentLayout.patch
        let sampled = mask[0, 0, 0..., .stride(by: patch), .stride(by: patch)]
        return (sampled * Float(timestep)).reshaped([1, -1])
    }
}
