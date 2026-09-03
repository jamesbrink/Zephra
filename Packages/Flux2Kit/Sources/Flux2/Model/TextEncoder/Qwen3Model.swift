import Foundation
import MLX
import MLXNN

/// The Qwen3 decoder stack: embeddings and layers, and deliberately nothing after them.
///
/// Named `model` because that is the prefix the published checkpoint uses. There is no final
/// norm here, and the stack is shorter than the checkpoint's: FLUX.2 reads the running hidden
/// state part-way up rather than the encoder's output, so everything past the deepest tap is
/// weight that would be loaded and never run.
final class Qwen3Model: Module {
    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    @ModuleInfo(key: "layers") var layers: [Qwen3DecoderLayer]

    /// Builds the stack `configuration.layersNeeded` layers deep -- 27, not the 36 the config's
    /// `num_hidden_layers` reports.
    ///
    /// This is the one number in the port that a "just read the config" tidy-up would quietly
    /// break. The published config still says 36 because it describes Qwen3-4B whole, and the
    /// quantized snapshot Zephra builds omits layers 27 through 35 and the final norm entirely.
    /// Building 36 layers against those weights fails to load; building 36 against the published
    /// checkpoint loads and then carries two spare gigabytes for nothing.
    ///
    /// - Parameter layersNeeded: Overrides that depth, for a stack tapped somewhere else. The
    ///   parity fixture is a six-layer doll's house tapped at 2, 4, and 6.
    init(_ configuration: Flux2TextEncoderConfiguration, layersNeeded: Int? = nil) {
        _embedTokens.wrappedValue = Embedding(
            embeddingCount: configuration.vocabSize, dimensions: configuration.hiddenSize)
        _layers.wrappedValue = (0..<(layersNeeded ?? configuration.layersNeeded)).map { _ in
            Qwen3DecoderLayer(configuration)
        }
    }

    /// The running hidden state at each of `taps`, in the order asked for.
    ///
    /// Taps count the way the reference's `output_hidden_states` does: tap 0 is the embedding
    /// output, before any layer, and tap `n` is the state after `n` layers have run. Off by one
    /// here is a mistake that produces a plausible image of the wrong prompt, so it is worth
    /// saying twice: `taps: [9]` means nine layers have run, not eight.
    ///
    /// One asymmetry in the reference is worth knowing about and does not apply here. Its *last*
    /// hidden state, and only that one, has been through the final norm. klein's taps stop at 27
    /// of 36, so all three are raw layer outputs and the norm this stack does not have is a norm
    /// nothing wanted. A stack tapped at its own last layer would disagree with the reference,
    /// which is why the parity fixture is eight layers deep and tapped at six.
    ///
    /// - Parameters:
    ///   - tokens: Padded token ids, `[batch, length]`.
    ///   - validCount: Real tokens at the front of each row. The rest are padding, hidden from
    ///     every query by the mask but still carried forward as conditioning.
    ///   - taps: Which states to keep.
    func hiddenStates(_ tokens: MLXArray, validCount: Int, taps: [Int]) -> [MLXArray] {
        var x = embedTokens(tokens)
        let mask = Qwen3AttentionMask.causalAndPadding(
            length: tokens.dim(1), validCount: validCount, dtype: x.dtype)

        let wanted = Set(taps)
        var captured: [Int: MLXArray] = wanted.contains(0) ? [0: x] : [:]
        for (index, layer) in layers.enumerated() {
            x = layer(x, mask: mask)
            if wanted.contains(index + 1) { captured[index + 1] = x }
        }

        return taps.map { tap in
            guard let state = captured[tap] else {
                preconditionFailure(
                    "tap \(tap) is past the \(layers.count) layers this stack was built with")
            }
            return state
        }
    }
}
