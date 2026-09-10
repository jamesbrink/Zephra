import Foundation
import MLX
import MLXNN
import ZephraMLX

/// Wan 2.2's video autoencoder, `AutoencoderKLWan` in the residual configuration: pixels to
/// a 48-channel latent at a sixteenth of the size and a quarter of the frames, and back.
///
/// The two halves and the two point-wise convolutions between them sit under the checkpoint's
/// own keys, `encoder`, `decoder`, `quant_conv` and `post_quant_conv`, and the whole tree
/// computes in the dtype its weights arrive in: float32 in the release and in the fixtures,
/// bfloat16 as the pipeline loads it. Activations are channels-last
/// inside; the latent crosses both doors channels-first, `[batch, channels, frames, height,
/// width]`, because that is how every loop and every reference holds it, and pixels come in
/// channels-first for the same reason and go out channels-last, `[batch, frames, height,
/// width, 3]`, since that is what an encoder of frames reads.
///
/// A clip is walked in the reference's chunks, the first frame alone and then four at a time
/// on the way in and one latent frame at a time on the way out, each chunk carrying the
/// convolutions' cache forward and evaluated before the next starts, so the peak is a chunk's
/// and not the clip's. That is also why a frame count must be `1 + 4k`: the reference drops a
/// trailing partial chunk without a word, and this refuses it instead.
public final class WanVideoAutoencoder: Module {
    @ModuleInfo(key: "encoder") var encoder: WanEncoder3d
    @ModuleInfo(key: "decoder") var decoder: WanDecoder3d
    @ModuleInfo(key: "quant_conv") var quantConv: WanCausalConv3d
    @ModuleInfo(key: "post_quant_conv") var postQuantConv: WanCausalConv3d

    public let configuration: WanVAEConfiguration

    public init(_ configuration: WanVAEConfiguration = .wan22) {
        self.configuration = configuration
        _encoder.wrappedValue = WanEncoder3d(configuration)
        _decoder.wrappedValue = WanDecoder3d(configuration)
        _quantConv.wrappedValue = WanCausalConv3d(
            inputChannels: 2 * configuration.zDim, outputChannels: 2 * configuration.zDim, kernelSize: 1)
        _postQuantConv.wrappedValue = WanCausalConv3d(
            inputChannels: configuration.zDim, outputChannels: configuration.zDim, kernelSize: 1)
        super.init()
    }

    /// The dtype the autoencoder computes in: the one its weights hold.
    public var dtype: DType { quantConv.weight.dtype }

    /// Fills the tree from the release's `vae/*.safetensors` tensors. Every parameter must be
    /// covered exactly: a half with a stage's weights missing would still run.
    public func load(weights: [String: MLXArray]) throws {
        try update(parameters: ModuleParameters.unflattened(WanVAEWeights.sanitized(weights)), verify: .all)
    }

    /// Encodes pixels, `[batch, 3, frames, height, width]` in the range -1 to 1 with `1 + 4k`
    /// frames, to the latent distribution's mean, `[batch, channels, frames', height', width']`
    /// -- `sample_mode: "argmax"`, the first half of what `quant_conv` writes. Raw: the
    /// pipeline normalises it with `WanLatentNormalization` before the transformer sees it.
    public func encode(_ video: MLXArray) -> MLXArray {
        let frames = video.dim(2)
        precondition((frames - 1) % configuration.temporalCompression == 0, "a clip is 1 + 4k frames")
        let patched = WanPatchify.patchified(
            video.transposed(0, 2, 3, 4, 1).asType(dtype), patch: configuration.patchSize)
        let cache = WanFeatureCache()
        var chunks: [MLXArray] = []
        var start = 0
        while start < frames {
            let end = start == 0 ? 1 : start + configuration.temporalCompression
            chunks.append(run(patched[0..., start..<end], cache: cache) { encoder($0, cache: cache) })
            start = end
        }
        let moments = quantConv(concatenated(chunks, axis: 1))
        return moments[.ellipsis, 0..<configuration.zDim].transposed(0, 4, 1, 2, 3)
    }

    /// Decodes a latent in the autoencoder's own space, `[batch, channels, frames', height',
    /// width']`, to pixels `[batch, frames, height, width, 3]` clamped to -1 to 1, as the
    /// reference's `decode` clamps them.
    ///
    /// With a `tile`, an edge in latent cells, the clip is decoded in overlapping spatial
    /// tiles through `TiledDecode`, each tile walking every frame with a cache of its own, and
    /// cross-faded where they meet: the decode's peak is then the tile's and not the clip's.
    /// The 1 x 1 `post_quant_conv` runs first, whole, since it reads no neighbour.
    public func decode(_ latent: MLXArray, tile: Int? = nil) -> MLXArray {
        let x = postQuantConv(latent.transposed(0, 2, 3, 4, 1).asType(dtype))
        guard let tile, tile < max(x.dim(2), x.dim(3)) else { return decodeWhole(x) }
        // Frames ride in the batch slot: the tiler cuts and joins axes 1 and 2 and passes the
        // rest through, and every tile decodes to the same frame count.
        let tiled = TiledDecode.run(x[0], tile: tile, scale: configuration.spatialCompression) { patch in
            decodeWhole(patch[.newAxis])[0]
        }
        return tiled[.newAxis]
    }

    /// The whole of `x`, `[batch, frames', height', width', channels]` past the 1 x 1
    /// convolution, one latent frame per chunk.
    private func decodeWhole(_ x: MLXArray) -> MLXArray {
        let cache = WanFeatureCache()
        let chunks = (0..<x.dim(1)).map { frame in
            run(x[0..., frame..<(frame + 1)], cache: cache) {
                decoder($0, cache: cache, firstChunk: frame == 0)
            }
        }
        let pixels = WanPatchify.unpatchified(concatenated(chunks, axis: 1), patch: configuration.patchSize)
        return clip(pixels, min: -1, max: 1)
    }

    /// One chunk through `body` on a rewound cache, evaluated with what the cache now carries
    /// so the graph is cut at every chunk.
    private func run(_ chunk: MLXArray, cache: WanFeatureCache, _ body: (MLXArray) -> MLXArray) -> MLXArray {
        cache.beginChunk()
        let output = body(chunk)
        eval([output] + cache.arrays)
        return output
    }
}
