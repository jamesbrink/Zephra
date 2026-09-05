import Foundation
import MLX
import MLXNN

/// Reading a component's weights into a module tree, packed or not.
///
/// Packed weights need the tree reshaped before they can land: a `Linear` cannot hold a
/// four-bit tensor, so it has to become a `QuantizedLinear` first. Which layers were packed is
/// decided the way the weights themselves say — a layer is packed if and only if the shard
/// carries a `.scales` for it — rather than by trusting the manifest's naming to line up with
/// the module paths. The manifest is consulted only for how finely, which is the one thing the
/// weights cannot say for themselves.
public enum PackedWeightLoading {
    /// Reshapes `model` so it can hold whichever of `weights` are packed, then loads them.
    ///
    /// Tensors the tree has no place for are ignored, which is what lets an unpacked snapshot
    /// load into a text encoder that stops at the last tapped layer. Tensors the tree wants and
    /// the weights lack are a hard failure.
    ///
    /// - Parameters:
    ///   - model: The module tree to fill.
    ///   - weights: The component's tensors, under the names the tree uses.
    ///   - manifest: How finely each layer was packed, when the snapshot is a packed one.
    ///   - checkpointName: The manifest's name for a module path, when the two differ.
    public static func load(
        into model: Module,
        weights: [String: MLXArray],
        manifest: PackedSnapshotManifest?,
        checkpointName: (String) -> String = { $0 }
    ) throws {
        let packed = Set(
            weights.keys.filter { $0.hasSuffix(".scales") }
                .map { String($0.dropLast(".scales".count)) })
        // Packed tensors with nothing saying how finely would land in an unpacked tree and
        // fail on shape; the refusal names the tensor instead, before the tree is touched.
        guard let manifest else {
            if let first = packed.min() {
                throw PackedSnapshotError.packedWithoutManifest(firstKey: first + ".scales")
            }
            try update(model, with: weights)
            return
        }
        // Every leaf is claimed, not just the packed ones, and the unpacked ones are handed
        // straight back unchanged. MLX rebuilds the tree from exactly the paths it is given,
        // so claiming only some elements of an array leaves a sparse one -- which becomes a
        // dictionary, and no longer matches the array it is meant to replace. A feed-forward
        // built around an activation, or a modulation behind one, is such an array.
        var quantizing = false
        quantize(
            model: model,
            filter: { path, _ in
                quantizing = packed.contains(path)
                guard quantizing else { return (64, 4, .affine) }
                let precision = manifest.precision(of: checkpointName(path))
                return (precision.groupSize, precision.bits, .affine)
            },
            apply: { layer, groupSize, bits, mode in
                guard quantizing else { return layer }
                return quantizeSingle(
                    layer: layer, groupSize: groupSize, bits: bits, mode: mode)
            }
        )
        try update(model, with: weights)
    }

    /// Casts every float32 parameter in `model` to `dtype`, leaving the packed integer
    /// weights alone.
    ///
    /// The packer writes scales and biases in float32, as the reference export does, and
    /// MLX's quantized matmul takes its output dtype from them: one float32 scale and the
    /// whole stream after that layer is float32, whatever the input was. At a 4096-token image
    /// that puts the attention off the fused kernel. So the scales are brought down to the
    /// activation dtype once, at load — and before a `LayerWeightStream` is attached, so the
    /// stream captures the cast nodes and keeps the dtype on every later pass.
    public static func castFloatParameters(of model: Module, to dtype: DType) {
        guard dtype != .float32 else { return }
        model.update(
            parameters: model.parameters().mapValues { $0.dtype == .float32 ? $0.asType(dtype) : $0 })
    }

    /// Fills `model` with the tensors in `weights` it has a place for.
    private static func update(_ model: Module, with weights: [String: MLXArray]) throws {
        let wanted = Set(model.parameters().flattened().map(\.0))
        try model.update(
            parameters: ModuleParameters.unflattened(weights.filter { wanted.contains($0.key) }),
            verify: .all)
    }
}
