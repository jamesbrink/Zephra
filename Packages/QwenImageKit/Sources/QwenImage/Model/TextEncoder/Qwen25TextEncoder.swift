import Foundation
import MLX
import MLXNN

/// Qwen-Image's conditioning encoder: the language half of Qwen2.5-VL-7B.
///
/// The vision tower is deliberately absent. Text-to-image supplies token ids and nothing else,
/// so the ViT is never run — and it, together with `lm_head`, is 391 of the checkpoint's 729
/// tensors, none of which this loads.
public final class Qwen25TextEncoder: Module {
    @ModuleInfo(key: "model") var model: Qwen25Model

    /// Builds an encoder shaped by `configuration`. Weights arrive separately.
    public init(_ configuration: QwenImageTextEncoderConfiguration) {
        _model.wrappedValue = Qwen25Model(configuration)
    }

    /// The conditioning for one prompt: hidden states with the template's prefix removed.
    ///
    /// - Parameters:
    ///   - tokens: The templated prompt's ids, `[batch, length]`.
    ///   - dropping: How many leading tokens the template contributes, which the reference
    ///     drops before conditioning. For Qwen-Image's own template that is 34.
    public func callAsFunction(_ tokens: MLXArray, dropping prefix: Int) throws -> MLXArray {
        let hidden = try model(tokens)
        guard prefix > 0 else { return hidden }
        precondition(
            hidden.shape[1] > prefix,
            "the prompt is shorter than the template prefix it is supposed to drop")
        return hidden[0..., prefix...]
    }
}
