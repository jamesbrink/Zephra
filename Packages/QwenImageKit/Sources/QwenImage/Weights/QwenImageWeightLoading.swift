import Foundation
import MLX
import MLXNN
import ZephraMLX

/// Reading a component's weights off disk and into a module tree.
///
/// Packed weights need the tree reshaped before they can land: a `Linear` cannot hold a
/// four-bit tensor, so it has to become a `QuantizedLinear` first. Which layers were packed is
/// decided the way the weights themselves say — a layer is packed if and only if the shard
/// carries a `.scales` for it — rather than by trusting the manifest's naming to line up with
/// the module paths. The manifest is consulted only for how finely, which is the one thing the
/// weights cannot say for themselves.
public enum QwenImageWeightLoading {
    /// Every tensor in a component's shards.
    ///
    /// Arrays come back unevaluated: only each shard's header is parsed, and a tensor is read
    /// from the file into memory the first time it is evaluated, so nothing is resident until
    /// it is used.
    public static func weights(in directory: URL) throws -> [String: MLXArray] {
        let shards = try shards(in: directory)
        var all: [String: MLXArray] = [:]
        for shard in shards {
            all.merge(try MLX.loadArrays(url: shard)) { first, _ in first }
        }
        return all
    }

    /// A component's shards, in the order `weights(in:)` reads them, so an index built over
    /// them and the dictionary read from them agree about which shard a tensor came from.
    public static func shards(in directory: URL) throws -> [URL] {
        let shards = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "safetensors" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !shards.isEmpty else {
            throw QwenImageConfigurationError.missingConfiguration(
                name: "*.safetensors", directory: directory)
        }
        return shards
    }

    /// Reshapes `model` so it can hold whichever of `weights` are packed, then loads them.
    ///
    /// - Parameters:
    ///   - model: The module tree to fill.
    ///   - weights: The component's tensors, as read from its shards.
    ///   - manifest: How finely each layer was packed, when the snapshot is a packed one.
    public static func load(
        into model: Module,
        weights rawWeights: [String: MLXArray],
        manifest: QwenImageQuantizationManifest?
    ) throws {
        let weights = QwenImageTransformerWeights.sanitized(rawWeights)
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
        // dictionary, and no longer matches the array it is meant to replace. Both the
        // feed-forward's `net` and the modulation's slots are arrays with gaps in them,
        // because the reference has an activation and a dropout where nothing is packed.
        var quantizing = false
        quantize(
            model: model,
            filter: { path, _ in
                quantizing = packed.contains(path)
                guard quantizing else { return (64, 4, .affine) }
                let precision = manifest.precision(
                    of: QwenImageTransformerWeights.checkpointName(of: path))
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

    /// Fills `model` with the tensors in `weights` it has a place for.
    private static func update(_ model: Module, with weights: [String: MLXArray]) throws {
        let wanted = Set(model.parameters().flattened().map(\.0))
        try model.update(
            parameters: ModuleParameters.unflattened(weights.filter { wanted.contains($0.key) }),
            verify: .all)
    }

    /// Casts every float32 parameter in `model` to `dtype`, leaving the packed integer
    /// weights alone.
    ///
    /// The packer writes scales and biases in float32, as the reference export does, and
    /// MLX's quantized matmul takes its output dtype from them: one float32 scale and the
    /// whole stream after that layer is float32, whatever the input was. At a 4096-token image
    /// that puts the attention off the fused kernel. So the scales are brought down to the
    /// activation dtype once, at load, and before a `LayerWeightStream` is attached, so the
    /// stream captures the cast nodes and keeps the dtype on every later pass.
    ///
    /// A copy of `Flux2WeightLoading.castFloatParameters`; M8 of the audit remediation moves
    /// both into one shared loader in `ZephraMLX`.
    public static func castFloatParameters(of model: Module, to dtype: DType) {
        guard dtype != .float32 else { return }
        model.update(
            parameters: model.parameters().mapValues { $0.dtype == .float32 ? $0.asType(dtype) : $0 })
    }
}
