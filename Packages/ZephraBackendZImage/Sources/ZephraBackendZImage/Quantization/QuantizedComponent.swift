import Foundation

/// The parts of a Z-Image snapshot whose linear weights get packed. The VAE is left alone:
/// it is a fifth of a gigabyte and quantizing it costs visible artefacts for no real saving.
public enum QuantizedComponent: String, CaseIterable, Sendable {
    case transformer
    case textEncoder = "text_encoder"

    /// The subdirectory the component's shards live in, in both the source and the output.
    public var directoryName: String { rawValue }

    /// The manifest name for a tensor of this component.
    ///
    /// The loader looks a layer up by the module path it walks — bare `layers.0.attention.to_q`
    /// for the transformer, and `model.…` for the text encoder, whose module tree is rooted at
    /// `encoder.` and mapped back by `ZImageQuantizer.textEncoderTensorName`. Writing the names
    /// that way, rather than prefixing them with the component as the reference 8-bit export
    /// does, is what makes the per-layer `bits` and `group_size` in the manifest take effect.
    public func manifestName(forWeightBase base: String) -> String {
        base
    }
}
