import Foundation
import MLX
import MLXNN

/// FLUX.2 klein's conditioning encoder: the first 27 layers of Qwen3-4B.
///
/// The transformer does not read a language model's output. It reads the running hidden state
/// after three of the layers and lays the three side by side, which is where its 7680-wide text
/// stream comes from: three taps of a 2560-wide model. Nothing after the deepest tap is built,
/// so `model.norm` and layers 27 through 35 -- 100 of the checkpoint's 398 tensors -- are never
/// loaded and never run.
public final class Qwen3TextEncoder: Module {
    @ModuleInfo(key: "model") var model: Qwen3Model

    /// Which layers are tapped, in the order they are concatenated.
    public let taps: [Int]

    /// Builds an encoder shaped by `configuration`. Weights arrive separately.
    ///
    /// - Parameter taps: Overrides the configuration's `hiddenStateTaps`, which is `[9, 18, 27]`
    ///   for the published model. The stack is built exactly as deep as the deepest tap, so this
    ///   sets the layer count too. The parity fixture is a six-layer doll's house tapped at 2,
    ///   4, and 6, which is the only reason this is a parameter rather than a constant.
    public init(_ configuration: Flux2TextEncoderConfiguration, taps: [Int]? = nil) {
        let taps = taps ?? configuration.hiddenStateTaps
        self.taps = taps
        _model.wrappedValue = Qwen3Model(configuration, layersNeeded: taps.max() ?? 0)
    }

    /// The conditioning for one prompt: `[batch, length, hidden * taps.count]`.
    ///
    /// The taps are concatenated along the last axis, so each position carries its tapped states
    /// end to end. That is the same layout the reference reaches by stacking on a new axis and
    /// permuting it behind the sequence -- tap-major within a position, not position-major
    /// within a tap. Getting it the other way round is a transpose the shapes would not catch.
    ///
    /// - Parameters:
    ///   - tokens: Padded token ids, `[batch, length]`. klein pads to 512 and conditions on all
    ///     512, padding included.
    ///   - validCount: Real tokens at the front. The padded positions attend to the prefix and
    ///     to nothing else, which is what makes their states reproducible.
    ///
    /// Throws only when the stack is streamed; see `Qwen3Model.stream`.
    public func callAsFunction(_ tokens: MLXArray, validCount: Int) throws -> MLXArray {
        MLX.concatenated(
            try model.hiddenStates(tokens, validCount: validCount, taps: taps), axis: -1)
    }
}
