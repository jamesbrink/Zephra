import Foundation

/// The precision to use for each component of one quantized build.
///
/// The two are separate because the text encoder and the transformer do not degrade at the same
/// rate: a Qwen encoder that has lost too much precision garbles the prompt, while the diffusion
/// transformer mostly loses fine texture. Keeping the encoder at eight bits costs about a
/// gigabyte and is the first thing to try if a four-bit build stops following prompts.
public struct QuantizationRecipe: Hashable, Sendable {
    /// Precision for the diffusion transformer, which dominates both size and step time.
    public let transformer: QuantizationPrecision
    /// Precision for the Qwen text encoder.
    public let textEncoder: QuantizationPrecision

    /// Creates a recipe with a precision chosen per component.
    public init(transformer: QuantizationPrecision, textEncoder: QuantizationPrecision) {
        self.transformer = transformer
        self.textEncoder = textEncoder
    }

    /// Creates a recipe that treats every component the same way.
    public init(bits: Int, groupSize: Int) throws {
        let precision = try QuantizationPrecision(bits: bits, groupSize: groupSize)
        self.init(transformer: precision, textEncoder: precision)
    }

    /// The precision this recipe applies to one component.
    public func precision(for component: QuantizedComponent) -> QuantizationPrecision {
        switch component {
        case .transformer: transformer
        case .textEncoder: textEncoder
        }
    }

    /// Whether every component is packed the same way, which is what lets the manifest's
    /// top-level `bits` and `group_size` stand alone as a correct description of the build.
    public var isUniform: Bool {
        transformer == textEncoder
    }

    /// How the recipe reads in a log line.
    public var summary: String {
        isUniform
            ? transformer.summary
            : "transformer \(transformer.summary); text encoder \(textEncoder.summary)"
    }
}
