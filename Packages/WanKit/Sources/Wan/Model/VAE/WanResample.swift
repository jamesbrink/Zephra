import Foundation
import MLX
import MLXNN

/// Halves or doubles a clip: `downsampler` after an encoder stage, `upsampler` after a
/// decoder stage.
///
/// Space is resized frame by frame through `resample`, a resize and a 3 x 3 convolution. Time,
/// in the `3d` modes, goes through `time_conv`, a causal convolution three deep and one wide,
/// which is where the first chunk is special: a temporal upsampler lets its first chunk
/// through without doubling it, and a temporal downsampler lets its first chunk through
/// without halving it, only remembering it. That is what maps the first pixel frame to the
/// first latent frame alone, and the reference's cache is what makes it happen, so the cache
/// here is not optional.
///
/// The convolution keeps the width it is given: in the residual layout the reference builds
/// every upsampler with `upsample_out_dim` equal to its stage width.
final class WanResample: Module {
    @ModuleInfo(key: "resample") var resample: (WanSpatialResize, Conv2d)
    @ModuleInfo(key: "time_conv") var timeConv: WanCausalConv3d?

    let mode: WanResampleMode

    init(channels: Int, mode: WanResampleMode) {
        self.mode = mode
        _resample.wrappedValue = (
            WanSpatialResize(mode: mode),
            mode.upsamples
                ? Conv2d(inputChannels: channels, outputChannels: channels, kernelSize: 3, padding: 1)
                : Conv2d(inputChannels: channels, outputChannels: channels, kernelSize: 3, stride: 2)
        )
        _timeConv.wrappedValue =
            switch mode {
            case .upsample3d:
                WanCausalConv3d(
                    inputChannels: channels, outputChannels: 2 * channels,
                    kernelSize: [3, 1, 1], padding: [1, 0, 0])
            case .downsample3d:
                WanCausalConv3d(
                    inputChannels: channels, outputChannels: channels,
                    kernelSize: [3, 1, 1], stride: [2, 1, 1])
            case .upsample2d, .downsample2d:
                nil
            }
        super.init()
    }

    func callAsFunction(_ x: MLXArray, cache: WanFeatureCache) -> MLXArray {
        var x = x
        if mode == .upsample3d {
            x = doubledInTime(x, cache: cache)
        }
        let (batch, frames) = (x.dim(0), x.dim(1))
        let resized = resample.1(resample.0(x.reshaped([batch * frames, x.dim(2), x.dim(3), x.dim(4)])))
        x = resized.reshaped([batch, frames, resized.dim(1), resized.dim(2), resized.dim(3)])
        if mode == .downsample3d {
            x = halvedInTime(x, cache: cache)
        }
        return x
    }

    /// `time_conv` writes two channels for every one, and the pair becomes two frames: the
    /// first half of the channels the even frame, the second half the odd. The first chunk is
    /// let through as it is and marked `skipped`; the chunk after it carries a zero frame in
    /// place of the frame the skip did not keep.
    private func doubledInTime(_ x: MLXArray, cache: WanFeatureCache) -> MLXArray {
        cache.advance { carry in
            guard let timeConv else { preconditionFailure("upsample3d has a time_conv") }
            switch carry {
            case .nothing:
                return (x, .skipped)
            case .skipped, .frames:
                let carried: MLXArray? = if case .frames(let frames) = carry { frames } else { nil }
                var keep = WanCausalConv3d.lastFrames(of: x, 2)
                if keep.dim(1) < 2 {
                    let before = carried.map { WanCausalConv3d.lastFrames(of: $0, 1) } ?? MLXArray.zeros(like: keep)
                    keep = concatenated([before, keep], axis: 1)
                }
                return (Self.interleaved(timeConv(x, carrying: carried)), .frames(keep))
            }
        }
    }

    /// `[b, f, h, w, 2c]` to `[b, 2f, h, w, c]`: channel half first, then frame.
    static func interleaved(_ x: MLXArray) -> MLXArray {
        let (batch, frames, height, width) = (x.dim(0), x.dim(1), x.dim(2), x.dim(3))
        return x.reshaped([batch, frames, height, width, 2, x.dim(4) / 2])
            .transposed(0, 1, 4, 2, 3, 5)
            .reshaped([batch, 2 * frames, height, width, x.dim(4) / 2])
    }

    /// `time_conv` here has stride two and no padding, and reads the last frame carried in
    /// front of the chunk: a four-frame chunk becomes two, a two-frame chunk one. The first
    /// chunk is let through untouched and only its last frame is kept -- the reference keeps
    /// the whole chunk and reads that frame alone, so nothing else of it is ever used.
    private func halvedInTime(_ x: MLXArray, cache: WanFeatureCache) -> MLXArray {
        cache.advance { carry in
            guard let timeConv else { preconditionFailure("downsample3d has a time_conv") }
            let last = WanCausalConv3d.lastFrames(of: x, 1)
            switch carry {
            case .nothing:
                return (x, .frames(last))
            case .frames(let carried):
                return (timeConv(concatenated([WanCausalConv3d.lastFrames(of: carried, 1), x], axis: 1)), .frames(last))
            case .skipped:
                preconditionFailure("only a temporal upsampler skips")
            }
        }
    }
}
