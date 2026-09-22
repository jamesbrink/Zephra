import Foundation
import MLX
import MLXNN

/// The tower's patch embedding: a `Conv3d` with kernel and stride both `[2, 16, 16]`, run here
/// as a plain linear over the 1536 numbers that kernel covers.
///
/// The convolution never overlaps — kernel equals stride — so every output is one dot product
/// against one patch, and the processor has already flattened the picture into exactly those
/// patches. `3 * 2 * 16 * 16 = 1536` is the kernel's own receptive field, laid out
/// `(channel, frame, row, column)`, which is the axis order PyTorch stores `[1152, 3, 2, 16,
/// 16]` in. So the stored kernel reshaped to `[1152, 1536]` **is** the linear's weight, with no
/// transpose, and `Qwen3VLVisionWeights` does that reshape once on the way in.
///
/// A still picture is duplicated along the frame axis to fill `temporal_patch_size`, which the
/// preprocessing does with a broadcast rather than a copy.
final class Qwen3VLVisionPatchEmbed: Module, UnaryLayer {
    @ModuleInfo(key: "proj") var projection: Linear

    init(_ configuration: Qwen3VLTextConfiguration.Vision) {
        let patch =
            3 * configuration.temporalPatchSize * configuration.patchSize * configuration.patchSize
        _projection.wrappedValue = Linear(patch, configuration.hiddenSize, bias: true)
    }

    /// `[patches, 1536]` in, `[patches, hidden]` out.
    func callAsFunction(_ patches: MLXArray) -> MLXArray { projection(patches) }
}
