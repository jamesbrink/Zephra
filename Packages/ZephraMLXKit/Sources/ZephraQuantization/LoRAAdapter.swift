import Foundation
import MLX

/// A set of low-rank adapters, merged into the weights they modify on the way past the packer.
///
/// A distilled variant of a model — a four-step schedule in place of a fifty-step one — usually
/// ships as an adapter rather than a whole checkpoint, because the difference is a few hundred
/// megabytes against tens of gigabytes. Merging it here rather than at load is what keeps the
/// runtime free of adapter code: the packed snapshot is simply the distilled model, and nothing
/// downstream knows an adapter was ever involved.
///
/// The arithmetic is one line — `W += (alpha / rank) * (up @ down)` — and everything else in
/// here is naming. Exports disagree about what the two factors are called and about which
/// prefix, if any, sits in front of the module path, so this accepts every spelling in
/// circulation and reduces them to the base weight key the checkpoint itself uses.
public final class LoRAAdapter {
    /// The two factors and the scale that multiplies their product.
    private struct Update {
        var down: MLXArray?
        var up: MLXArray?
        var alpha: Float?
    }

    /// Updates by the key of the weight each one modifies, `.weight` suffix and all.
    private let updates: [String: Update]

    /// The weights this adapter has been asked to merge so far.
    ///
    /// Kept here rather than tallied by the caller because it is the adapter's own question:
    /// an adapter written against different module names matches nothing, merges nothing, and
    /// hands back the base model, which looks exactly like a build that worked. A run reads
    /// `unmatchedKeys` afterwards and refuses rather than shipping half a distillation. A
    /// conversion is one pass on one thread, so this needs no protection.
    public private(set) var mergedKeys: Set<String> = []

    /// The weights this adapter names that it was never asked about.
    public var unmatchedKeys: [String] { Set(updates.keys).subtracting(mergedKeys).sorted() }

    /// Whether this adapter has something to say about `key`.
    public func modifies(_ key: String) -> Bool { updates[key] != nil }

    /// How many weights this adapter modifies.
    public var count: Int { updates.count }

    /// Reads every adapter file into one index.
    ///
    /// Later files win on a key they share with an earlier one, which is what stacking two
    /// adapters means; in practice there is one.
    public init(contentsOf urls: [URL]) throws {
        var updates: [String: Update] = [:]
        for url in urls {
            for (name, tensor) in try MLX.loadArrays(url: url) {
                guard let (key, part) = Self.parse(name) else { continue }
                switch part {
                case .down: updates[key, default: Update()].down = tensor
                case .up: updates[key, default: Update()].up = tensor
                case .alpha: updates[key, default: Update()].alpha = tensor.item(Float.self)
                }
            }
        }
        // A factor with no partner is a truncated or mis-shaped export, and merging half of one
        // silently produces a model that is neither the base nor the distilled variant.
        for (key, update) in updates where update.down == nil || update.up == nil {
            throw QuantizationError.incompleteAdapterLayer(key)
        }
        self.updates = updates
    }

    /// `weight` with this adapter's update for `key` added, in float32, or the weight unchanged
    /// when the adapter says nothing about it.
    ///
    /// Float32 throughout because the packer casts to float32 before quantizing anyway, and a
    /// rank-64 product accumulated in bfloat16 loses more than the merge is worth.
    public func applied(to weight: MLXArray, named key: String) throws -> MLXArray {
        guard let update = updates[key], let down = update.down, let up = update.up else {
            return weight
        }
        mergedKeys.insert(key)
        let rank = down.shape[0]
        let scale = (update.alpha ?? Float(rank)) / Float(rank)
        let delta = MLX.matmul(up.asType(.float32), down.asType(.float32)) * scale
        guard delta.shape == weight.shape else {
            throw QuantizationError.adapterShapeMismatch(
                key, adapter: delta.shape, weight: weight.shape)
        }
        return weight.asType(.float32) + delta
    }

    /// Which half of an update a tensor is.
    enum Part {
        case down, up, alpha
    }

    /// The weight key a LoRA tensor modifies, and which half of the update it is.
    ///
    /// Two spellings are in circulation for the factors — `lora_down`/`lora_up` from the kohya
    /// lineage and `lora_A`/`lora_B` from PEFT, the latter sometimes with an adapter name wedged
    /// in — and exports vary on whether the module path is bare or carries the component in
    /// front of it. Reducing all of that here means the rest of this type deals in checkpoint
    /// keys and nothing else.
    static func parse(_ name: String) -> (key: String, part: Part)? {
        var path = name
        for prefix in ["transformer.", "diffusion_model.", "lora_unet_"] where path.hasPrefix(prefix)
        {
            path = String(path.dropFirst(prefix.count))
        }
        for (suffix, part) in suffixes where path.hasSuffix(suffix) {
            return (String(path.dropLast(suffix.count)) + ".weight", part)
        }
        return nil
    }

    /// Recognised endings, longest first so `.lora_A.default.weight` is not read as `.weight`.
    private static let suffixes: [(String, Part)] = [
        (".lora_down.default.weight", .down),
        (".lora_up.default.weight", .up),
        (".lora_A.default.weight", .down),
        (".lora_B.default.weight", .up),
        (".lora_down.weight", .down),
        (".lora_up.weight", .up),
        (".lora_A.weight", .down),
        (".lora_B.weight", .up),
        (".alpha", .alpha),
    ]
}
