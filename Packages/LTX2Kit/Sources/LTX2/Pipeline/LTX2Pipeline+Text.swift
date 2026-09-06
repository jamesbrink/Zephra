import Foundation
import MLX

/// From a prompt to the conditioning the transformer attends to.
extension LTX2Pipeline {
    /// The connector's output for `prompt`, `[1, maxTokens, crossAttentionDim]` in the stream's
    /// dtype: tokenised and left-padded, run through every Gemma layer for all 49 hidden states,
    /// projected in float32, and passed through the connector, whose registers stand in for the
    /// padding so nothing downstream needs a mask.
    func encodePrompt(_ prompt: String, maxTokens: Int, with loaded: Loaded) throws -> MLXArray {
        let (ids, mask) = loaded.tokenizer.padded(prompt, to: maxTokens)
        let tokens = MLXArray(ids.map(Int32.init))[.newAxis, 0...]
        let padding = MLXArray(mask.map(Int32.init))[.newAxis, 0...]
        let states = try loaded.textEncoder.hiddenStates(tokens, padding: padding)
        let features = loaded.extractor(states, padding: padding)
        let context = loaded.connector(features.asType(loaded.activation), padding: padding)
        MLX.eval(context)
        return context
    }
}
