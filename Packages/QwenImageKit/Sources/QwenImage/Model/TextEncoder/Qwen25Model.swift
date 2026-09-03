import Foundation
import MLX
import MLXNN

/// The Qwen2.5 decoder stack: embeddings, layers, and the final norm.
///
/// Named `model` because that is the prefix the published checkpoint uses. Mirroring the
/// checkpoint's own shape means the weights load by their own names, with no remapping table to
/// drift out of date.
final class Qwen25Model: Module {
    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    @ModuleInfo(key: "layers") var layers: [Qwen25DecoderLayer]
    @ModuleInfo(key: "norm") var norm: RMSNorm

    init(_ configuration: QwenImageTextEncoderConfiguration) {
        _embedTokens.wrappedValue = Embedding(
            embeddingCount: configuration.vocabSize, dimensions: configuration.hiddenSize)
        _layers.wrappedValue = (0..<configuration.numHiddenLayers).map { _ in
            Qwen25DecoderLayer(configuration)
        }
        _norm.wrappedValue = RMSNorm(
            dimensions: configuration.hiddenSize, eps: configuration.rmsNormEps)
    }

    /// Runs the stack over `tokens`, `[batch, length]`, and returns the final hidden state.
    ///
    /// Qwen-Image conditions on this — the last hidden state, after the final norm — not on a
    /// layer part-way up and not on logits. Z-Image takes the second-to-last, so the difference
    /// is worth stating out loud.
    func callAsFunction(_ tokens: MLXArray) -> MLXArray {
        var x = embedTokens(tokens)
        let mask = Self.causalMask(tokens.shape[1], dtype: x.dtype)
        for layer in layers {
            x = layer(x, mask: mask)
        }
        return norm(x)
    }

    /// An additive mask that stops a token attending to anything after it.
    ///
    /// A prompt is encoded at its own length, with no padding, so this is the only mask needed:
    /// there are no pad positions to hide.
    static func causalMask(_ length: Int, dtype: DType) -> MLXArray? {
        guard length > 1 else { return nil }
        let positions = MLXArray(Array(0..<Int32(length)))
        let blocked = positions[0..., .newAxis] .< positions[.newAxis, 0...]
        return MLX.where(blocked, MLXArray(Float(-1e9)), MLXArray(Float(0))).asType(dtype)
    }
}
