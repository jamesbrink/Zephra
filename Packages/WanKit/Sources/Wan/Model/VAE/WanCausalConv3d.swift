import Foundation
import MLX
import MLXNN

/// A three-deep convolution that never reads a frame after the one it is writing.
///
/// The reference builds it from a plain `Conv3d` by moving all of the temporal padding to the
/// front: a kernel three deep configured with padding one gets two frames of zeros before the
/// clip and none after, so each output frame sees itself and the two before it. Space is
/// zero-padded symmetrically, which `Conv3d` does on its own. Between chunks the zeros are
/// replaced by frames carried from the previous chunk, as many as there are, and only what
/// they do not cover is padded.
///
/// This is `MLXNN.Conv3d` itself, so its `weight` and `bias` sit directly under the module's
/// key as the checkpoint spells them, `conv_in.weight` and not `conv_in.conv.weight`. The
/// kernel is MLX's `[out, kt, kh, kw, in]`; `WanVAEWeights` turns the checkpoint's
/// `[out, in, kt, kh, kw]` into it at load. Activations are channels-last, `[batch, frames,
/// height, width, channels]`.
final class WanCausalConv3d: Conv3d {
    /// Frames of zeros in front of a clip with nothing carried: twice the temporal padding the
    /// reference was configured with, the back half moved to the front.
    let frontPadding: Int

    /// `padding` is the reference's symmetric triple, before it is made causal.
    init(
        inputChannels: Int, outputChannels: Int, kernelSize: IntOrTriple,
        stride: IntOrTriple = 1, padding: IntOrTriple = 0
    ) {
        frontPadding = 2 * padding.first
        super.init(
            inputChannels: inputChannels, outputChannels: outputChannels, kernelSize: kernelSize,
            stride: stride, padding: [0, padding.second, padding.third])
    }

    override func callAsFunction(_ x: MLXArray) -> MLXArray {
        self(x, carrying: nil)
    }

    /// Convolves `x` with `carried` frames in front of it, zero-padding whatever of the causal
    /// window they leave uncovered.
    func callAsFunction(_ x: MLXArray, carrying carried: MLXArray?) -> MLXArray {
        var input = x
        var padding = frontPadding
        if let carried, frontPadding > 0 {
            input = concatenated([carried, x], axis: 1)
            padding -= carried.dim(1)
        }
        if padding > 0 {
            input = padded(input, widths: [0, [padding, 0], 0, 0, 0])
        }
        return taps(input)
    }

    /// The convolution as two-dimensional convolutions, one per output frame and temporal tap,
    /// summed over the taps.
    ///
    /// Not `Conv3d`'s own forward: MLX's three-dimensional convolution unfolds its input on
    /// Metal, and over a decoder stage a thousand channels wide at a clip's size that is both
    /// the slowest thing in a run and its memory peak (38 s and 25 GB of a 55 s clip at
    /// 832 x 480). Its two-dimensional convolution runs through a GEMM, and unfolds too, so
    /// the frames are not folded into the batch either: one output frame at a time keeps the
    /// unfolded input to a frame's worth, which is what bounds the decode's peak. The
    /// arithmetic is the reference's in another order. The temporal stride picks the frames;
    /// the spatial stride and padding are the layer's own.
    private func taps(_ input: MLXArray) -> MLXArray {
        let depth = weight.dim(1)
        let outputFrames = (input.dim(1) - depth) / stride.0 + 1
        let frames = (0..<outputFrames).map { frame -> MLXArray in
            var sum: MLXArray?
            for tap in 0..<depth {
                let y = conv2d(
                    input[0..., frame * stride.0 + tap], weight[0..., tap],
                    stride: .init((stride.1, stride.2)), padding: .init((padding.1, padding.2)),
                    dilation: .init((dilation.1, dilation.2)), groups: groups)
                sum = sum.map { $0 + y } ?? y
            }
            // Evaluated here, one frame at a time: a convolution unfolds its input on Metal,
            // and the buffers of every convolution in one command buffer stay allocated until
            // it has run, so twelve of them in flight over a 240 x 416 frame of 256 channels
            // held six gigabytes. One sync a frame keeps the unfold to one frame's taps.
            let frame = sum!
            eval(frame)
            return frame
        }
        let result = stacked(frames, axis: 1)
        return bias.map { result + $0 } ?? result
    }

    /// The reference's rule for a convolution inside a block: carry the last two frames of the
    /// chunk, and when the chunk is a single frame, top it up with the last frame carried
    /// before, so the next chunk always finds its causal window filled.
    func callAsFunction(_ x: MLXArray, cache: WanFeatureCache) -> MLXArray {
        cache.advance { carry in
            let carried: MLXArray? = if case .frames(let frames) = carry { frames } else { nil }
            var keep = Self.lastFrames(of: x, 2)
            if keep.dim(1) < 2, let carried {
                keep = concatenated([Self.lastFrames(of: carried, 1), keep], axis: 1)
            }
            return (self(x, carrying: carried), .frames(keep))
        }
    }

    /// Up to `count` frames from the end of `x`.
    static func lastFrames(of x: MLXArray, _ count: Int) -> MLXArray {
        x[0..., max(x.dim(1) - count, 0)...]
    }
}
