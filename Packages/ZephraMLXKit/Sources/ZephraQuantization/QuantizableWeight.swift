import Foundation

/// A tensor MLX is able to pack, recognised from its name and shape.
///
/// This answers a mechanical question and only a mechanical question: MLX's affine quantization
/// takes a two-dimensional matrix whose input width the group size divides, and the packed
/// result is stored as three keys hanging off one base. Whether a tensor *should* be packed is
/// policy, and policy lives in `QuantizedComponent`.
///
/// The split matters because the two questions have different answers per family and per tensor.
/// Precision is resolved first, because the group size it names is what divisibility is tested
/// against.
public struct QuantizableWeight: Hashable, Sendable {
    /// The tensor key with `.weight` removed, which is what `.scales` and `.biases` hang off.
    public let base: String
    /// Rows of the weight matrix: the layer's output width.
    public let outDim: Int
    /// Columns of the weight matrix: the layer's input width.
    public let inDim: Int

    /// Recognises a packable weight, or returns nil for a tensor MLX cannot pack at this group
    /// size, which must then be copied verbatim.
    public init?(name: String, shape: [Int], groupSize: Int) {
        guard name.hasSuffix(".weight"), shape.count == 2 else { return nil }
        guard shape[1] % groupSize == 0 else { return nil }
        self.base = String(name.dropLast(".weight".count))
        self.outDim = shape[0]
        self.inDim = shape[1]
    }

    /// The key MLX's packed weights are stored under, which is the original `.weight` key.
    public var weightKey: String { "\(base).weight" }
    /// The key holding one float32 scale per group.
    public var scalesKey: String { "\(base).scales" }
    /// The key holding one float32 bias per group.
    public var biasesKey: String { "\(base).biases" }
}
