import Foundation

/// The shape of the convolutional video encoder: how wide each stage is, how many blocks it
/// holds, and how each downsampler between two stages compresses time and space.
///
/// The mirror of `LTX2VideoDecoderLayout`, and it takes that type's `Stride` rather than one of
/// its own: a downsampler's `(temporal, spatial)` means the same pair of numbers read the other
/// way. LTX-2.5 publishes no `config.json` for its VAE, so `ltx25` is read off the checkpoint's
/// own key list, which `VAEEncoderWeightKeyTests` pins. Note that diffusers' constructor default
/// `layers_per_block=(4, 6, 6, 2, 2)` is **not** this checkpoint: its third stage holds four
/// blocks, not six.
public struct LTX2VideoEncoderLayout: Hashable, Sendable {
    /// One residual stage: its width and how many blocks run at it.
    public typealias Stage = LTX2VideoDecoderLayout.Stage
    /// How a downsampler between two stages compresses the clip.
    public typealias Stride = LTX2VideoDecoderLayout.Stride

    /// Colour channels the encoder reads, before the spatial patchify folds them into `patch²`
    /// times as many.
    public let inputChannels: Int
    /// Channels in the latent the encoder writes. `conv_out` produces one more: a broadcast
    /// log-variance nobody samples, since both reference pipelines encode with `sample_mode:
    /// "argmax"` and take the mean.
    public let latentChannels: Int
    /// The residual stages, first to last; one more than the downsamplers between them.
    public let stages: [Stage]
    /// The downsampler after each stage but the last.
    public let strides: [Stride]
    /// The spatial patch `conv_in` reads: `inputChannels` times this squared.
    public let patchSize: Int

    /// Creates a layout, requiring one downsampler between each pair of stages.
    public init(
        inputChannels: Int, latentChannels: Int, stages: [Stage], strides: [Stride], patchSize: Int
    ) {
        precondition(strides.count == stages.count - 1, "one downsampler between each pair of stages")
        self.inputChannels = inputChannels
        self.latentChannels = latentChannels
        self.stages = stages
        self.strides = strides
        self.patchSize = patchSize
    }

    /// The real LTX-2.5 conv encoder: patch 4 folding 3 colours into 48 channels, `[128, 3, 3,
    /// 3, 48]` in, 4/6/4/2/2 blocks at 128/256/512/1024/1024, downsamplers of 1x2x2, 2x1x1,
    /// 2x2x2 and 2x2x2, and `[129, 3, 3, 3, 1024]` out. Temporal compression is 8 (three
    /// temporal halvings, each keeping the first frame on its own, so `F' = (F - 1) / 8 + 1`)
    /// and spatial 32 (three spatial halvings times the patch).
    public static let ltx25 = LTX2VideoEncoderLayout(
        inputChannels: 3,
        latentChannels: 128,
        stages: [
            Stage(channels: 128, blocks: 4), Stage(channels: 256, blocks: 6),
            Stage(channels: 512, blocks: 4), Stage(channels: 1024, blocks: 2),
            Stage(channels: 1024, blocks: 2),
        ],
        strides: [
            Stride(temporal: 1, spatial: 2), Stride(temporal: 2, spatial: 1),
            Stride(temporal: 2, spatial: 2), Stride(temporal: 2, spatial: 2),
        ],
        patchSize: 4)

    /// Latent frames a clip of `pixelFrames` encodes to: the first frame on its own, the rest in
    /// groups of the temporal factor.
    public func latentFrames(forPixelFrames pixelFrames: Int) -> Int {
        strides.reduce(pixelFrames) { frames, stride in
            stride.temporal == 1 ? frames : (frames - 1) / stride.temporal + 1
        }
    }

    /// Latent cells an edge of `pixels` encodes to.
    public func latentCells(forPixels pixels: Int) -> Int {
        strides.reduce(pixels / patchSize) { $0 / $1.spatial }
    }
}
