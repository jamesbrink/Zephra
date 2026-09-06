import Foundation

/// The shape of the convolutional video decoder: how wide each stage is, how many blocks it
/// holds, and how each upsampler between two stages stretches time and space.
///
/// LTX-2.5 publishes no `config.json` for its VAE; the layout is fixed by the checkpoint and
/// diffusers' conversion pins it to LTX-2.3's, which `ltx25` spells out. A doll's-house layout
/// with the same stage pattern is what the parity fixture is dumped at.
public struct LTX2VideoDecoderLayout: Hashable, Sendable {
    /// One residual stage: its width and how many blocks run at it.
    public struct Stage: Hashable, Sendable {
        public let channels: Int
        public let blocks: Int

        public init(channels: Int, blocks: Int) {
            self.channels = channels
            self.blocks = blocks
        }
    }

    /// How an upsampler between two stages stretches the clip: by `temporal` in frames and by
    /// `spatial` on each of height and width.
    public struct Stride: Hashable, Sendable {
        public let temporal: Int
        public let spatial: Int

        public init(temporal: Int, spatial: Int) {
            self.temporal = temporal
            self.spatial = spatial
        }

        /// Channels per output channel the shuffle consumes.
        var factor: Int { temporal * spatial * spatial }
    }

    /// Channels in the latent the decoder reads.
    public let latentChannels: Int
    /// The residual stages, first to last; one more than the upsamplers between them.
    public let stages: [Stage]
    /// The upsampler after each stage but the last.
    public let strides: [Stride]
    /// The spatial patch `conv_out` writes: 3 colour channels times this squared.
    public let patchSize: Int

    /// Creates a layout, requiring one upsampler between each pair of stages.
    public init(latentChannels: Int, stages: [Stage], strides: [Stride], patchSize: Int) {
        precondition(strides.count == stages.count - 1, "one upsampler between each pair of stages")
        self.latentChannels = latentChannels
        self.stages = stages
        self.strides = strides
        self.patchSize = patchSize
    }

    /// The real LTX-2.5 conv decoder: `[1024, 3, 3, 3, 128]` in, 2/2/4/6/4 blocks at
    /// 1024/512/512/256/128, upsamplers of 2x2x2, 2x2x2, 2x1x1 and 1x2x2, patch 4. Temporal
    /// growth is 8 (three temporal doublings, each dropping its first frame, so
    /// `F = 8 (F' - 1) + 1`) and spatial growth 32 (three spatial doublings times the patch).
    public static let ltx25 = LTX2VideoDecoderLayout(
        latentChannels: 128,
        stages: [
            Stage(channels: 1024, blocks: 2), Stage(channels: 512, blocks: 2),
            Stage(channels: 512, blocks: 4), Stage(channels: 256, blocks: 6),
            Stage(channels: 128, blocks: 4),
        ],
        strides: [
            Stride(temporal: 2, spatial: 2), Stride(temporal: 2, spatial: 2),
            Stride(temporal: 2, spatial: 1), Stride(temporal: 1, spatial: 2),
        ],
        patchSize: 4)

    /// Pixel frames a latent of `latentFrames` decodes to.
    public func frames(forLatentFrames latentFrames: Int) -> Int {
        strides.reduce(latentFrames) { frames, stride in
            stride.temporal == 1 ? frames : frames * stride.temporal - 1
        }
    }

    /// Pixels an edge of `latentCells` decodes to.
    public func pixels(forLatentCells latentCells: Int) -> Int {
        strides.reduce(latentCells) { $0 * $1.spatial } * patchSize
    }
}
