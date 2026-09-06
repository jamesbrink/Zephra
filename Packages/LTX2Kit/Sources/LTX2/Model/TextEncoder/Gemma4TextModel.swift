import Foundation
import MLX
import MLXNN
import ZephraMLX

/// The Gemma 4 decoder stack LTX-2.5 conditions on: embeddings, 48 layers, and the final norm.
///
/// Unlike the other kits' encoders this one hands back *every* hidden state, 49 of them: the
/// scaled embedding, and the output of each layer, with the final norm applied to the last one
/// only, which is how the reference's `output_hidden_states` reports them. All 49 are the
/// conditioning, so every layer runs and nothing in the stack is skippable.
///
/// The module tree is the checkpoint's minus its `model.language_model.` prefix, which the
/// loader and the stream prepend, so the weights load by their own names.
final class Gemma4TextModel: Module {
    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    @ModuleInfo(key: "layers") var layers: [Gemma4DecoderLayer]
    @ModuleInfo(key: "norm") var norm: RMSNorm

    /// Set when the layers' weights are read from disk on each pass rather than held.
    var stream: LayerWeightStream<Gemma4DecoderLayer>?

    let configuration: Gemma4Configuration

    /// The checkpoint's prefix for every path in this tree.
    static let checkpointPrefix = "model.language_model."

    init(_ configuration: Gemma4Configuration) {
        self.configuration = configuration
        _embedTokens.wrappedValue = Embedding(
            embeddingCount: configuration.vocabSize, dimensions: configuration.hiddenSize)
        _layers.wrappedValue = (0..<configuration.numHiddenLayers).map {
            Gemma4DecoderLayer(configuration, layer: $0)
        }
        _norm.wrappedValue = RMSNorm(
            dimensions: configuration.hiddenSize, eps: configuration.rmsNormEps)
    }

    /// Every hidden state for `tokens`, `[batch, length]`, under `padding`, a `[batch, length]`
    /// mask of ones over the real tokens: `numHiddenLayers + 1` arrays of
    /// `[batch, length, hidden]`, the last of them normed.
    ///
    /// The embedding is scaled by the square root of the width in the stream's own dtype, as
    /// the reference does: on a bfloat16 model that rounds 61.97 to 62, and matching it matters
    /// more than the third digit.
    func hiddenStates(_ tokens: MLXArray, padding: MLXArray) throws -> [MLXArray] {
        var x = embedTokens(tokens)
        x = x * MLXArray(Float(configuration.hiddenSize).squareRoot()).asType(x.dtype)
        let masks = Gemma4AttentionMask.masks(
            padding: padding, slidingWindow: configuration.slidingWindow, dtype: x.dtype)
        var states = [x]
        if let stream {
            var index = 0
            try stream.run { layer in
                x = layer(x, mask: configuration.layer(at: index).isSliding ? masks.sliding : masks.full)
                states.append(x)
                index += 1
                return [x]
            }
        } else {
            for (index, layer) in layers.enumerated() {
                x = layer(x, mask: configuration.layer(at: index).isSliding ? masks.sliding : masks.full)
                states.append(x)
            }
        }
        states[states.count - 1] = norm(x)
        return states
    }
}
