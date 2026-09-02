import Foundation

/// A tensor the vendored loader expects to find packed, recognised from its name and shape.
///
/// The rule is copied from the export that produced `mzbac/Z-Image-Turbo-8bit`, because the
/// loader decides what is quantized by looking for a matching `.scales` key: pack a tensor the
/// reference build left alone and the module tree stops matching the weights. A tensor
/// qualifies when it is a two-dimensional `.weight`, is not an embedding or a norm, does not
/// belong to one of the two dictionary-keyed submodules the loader restores by hand
/// (`all_x_embedder`, `all_final_layer`), and has an input dimension the group size divides.
struct QuantizableWeight: Hashable, Sendable {
    /// The tensor key with `.weight` removed, which is what `.scales` and `.biases` hang off.
    let base: String
    /// Rows of the weight matrix: the layer's output width.
    let outDim: Int
    /// Columns of the weight matrix: the layer's input width.
    let inDim: Int

    /// Recognises a packable weight, or returns nil for a tensor that must be copied verbatim.
    init?(name: String, shape: [Int], groupSize: Int) {
        guard name.hasSuffix(".weight"), shape.count == 2 else { return nil }
        guard !Self.isEmbedding(name), !Self.isNorm(name), !Self.isDictionaryModule(name) else {
            return nil
        }
        guard shape[1] % groupSize == 0 else { return nil }
        self.base = String(name.dropLast(".weight".count))
        self.outDim = shape[0]
        self.inDim = shape[1]
    }

    /// The key MLX's packed weights are stored under, which is the original `.weight` key.
    var weightKey: String { "\(base).weight" }
    /// The key holding one float32 scale per group.
    var scalesKey: String { "\(base).scales" }
    /// The key holding one float32 bias per group.
    var biasesKey: String { "\(base).biases" }

    private static func isEmbedding(_ name: String) -> Bool {
        name.contains("embed") || name.contains("embedding")
    }

    private static func isNorm(_ name: String) -> Bool {
        name.contains("norm") || name.contains("layernorm")
    }

    private static func isDictionaryModule(_ name: String) -> Bool {
        name.hasPrefix("all_x_embedder") || name.hasPrefix("all_final_layer")
    }
}
