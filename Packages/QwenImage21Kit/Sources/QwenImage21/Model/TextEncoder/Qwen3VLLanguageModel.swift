import Foundation
import MLX
import MLXNN
import ZephraMLX

/// The Qwen3-VL decoder stack: the embedding table, all 36 layers, and deliberately nothing
/// after them.
///
/// **There is no final norm here, and that is the whole point.** The transformer conditions on
/// the output of decoder layer 35 *before* `model.language_model.norm`, which the reference
/// pipeline reaches by hooking that module to hand back its own input — from transformers 5.0
/// `hidden_states[-1]` is otherwise the normalised state, which is about a third of the signal
/// the transformer reads and shows up first in rendered text. Implementing the hook as "the
/// norm does not exist" is the honest Swift shape of it; `norm.weight` and `lm_head.weight` are
/// both omitted from a pack and never built. `PROVENANCE.md` records it.
///
/// Every layer is built, unlike klein's encoder, which stops at its deepest tap: 2.1 reads the
/// last layer, so nothing here is spare.
public final class Qwen3VLLanguageModel: Module {
    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    @ModuleInfo(key: "layers") var layers: [Qwen3VLDecoderLayer]

    /// Set when the layers' weights are read from disk on each pass rather than held.
    var stream: LayerWeightStream<Qwen3VLDecoderLayer>?

    private let rotary: Qwen3VLRotary

    /// Builds the stack shaped by `configuration`. Weights arrive separately.
    ///
    /// - Parameter layerCount: Overrides `num_hidden_layers`, for the doll's-house parity
    ///   fixture. The published stack is 36 deep and nothing reads it shallower.
    public init(_ configuration: Qwen3VLTextConfiguration.Text, layerCount: Int? = nil) {
        _embedTokens.wrappedValue = Embedding(
            embeddingCount: configuration.vocabSize, dimensions: configuration.hiddenSize)
        _layers.wrappedValue = (0..<(layerCount ?? configuration.numHiddenLayers)).map { _ in
            Qwen3VLDecoderLayer(configuration)
        }
        rotary = Qwen3VLRotary(
            headDim: configuration.headDim,
            theta: configuration.ropeTheta,
            mropeSection: configuration.ropeScaling.mropeSection)
    }

    /// The embedding table's rows for `tokens`, `[batch, length]`, before any layer runs.
    ///
    /// Separate from `hiddenStates` because a prompt with pictures replaces the rows at the
    /// image slots with the tower's output before layer 0 sees them.
    public func embedded(_ tokens: MLXArray) -> MLXArray { embedTokens(tokens) }

    /// The last layer's output for `embeddings`, `[batch, length, hidden]`, before the norm
    /// this stack does not have.
    ///
    /// - Parameters:
    ///   - embeddings: What layer 0 reads, the tower's slots already written in.
    ///   - positions: `[3, length]` of time, row and column indices. `Qwen3VLPositionIDs`
    ///     builds one for a prompt with pictures; `Qwen3VLRotary.textPositions` for one without.
    ///   - deepStack: The tower's three taps, added after layers 0, 1 and 2. Nil for text only.
    ///
    /// Throws only when streaming: a shard that changed under the model.
    public func hiddenStates(
        _ embeddings: MLXArray, positions: MLXArray, deepStack: Qwen3VLDeepStack? = nil
    ) throws -> MLXArray {
        var x = embeddings
        let mask = Qwen3VLAttentionMask.causal(length: x.dim(1), dtype: x.dtype)
        let (cos, sin) = rotary.tables(positions: positions, dtype: x.dtype)

        if let stream {
            // A stream hands back the layer and not its position, so the count is kept here:
            // a DeepStack tap added after the wrong layer is the one failure that still
            // produces a plausible picture, exactly as klein's encoder taps are counted.
            var depth = 0
            try stream.run { layer in
                x = layer(x, cos: cos, sin: sin, mask: mask)
                if let deepStack { x = deepStack.injected(x, after: depth) }
                depth += 1
                return [x]
            }
        } else {
            for (index, layer) in layers.enumerated() {
                x = layer(x, cos: cos, sin: sin, mask: mask)
                if let deepStack { x = deepStack.injected(x, after: index) }
            }
        }
        return x
    }
}
