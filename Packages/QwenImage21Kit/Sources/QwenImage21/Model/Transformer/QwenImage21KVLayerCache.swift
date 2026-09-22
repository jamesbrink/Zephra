import Foundation
import MLX

/// One layer's keys and values for the prefix: the text and every condition image.
///
/// Held **after the query and key norms and after the rotation**, which is where the reference
/// writes them, so a later step concatenates them in front of its own and attends without
/// recomputing a token of the prompt. Layout is head-major, `[batch, heads, prefixTokens,
/// headDim]` — the attention's own, which saves a transpose on every step of the run.
///
/// The stored slice is **copied, not kept as a view**. At batch one the prefix is the head of a
/// contiguous array, so a view would share its buffer and pin the whole prefill's keys and
/// values — target tokens and all — for every step of the denoising loop. At 1024 square that
/// is gigabytes held to save megabytes.
final class QwenImage21KVLayerCache {
    private(set) var key: MLXArray?
    private(set) var value: MLXArray?

    init() {}

    /// Keeps this layer's prefix.
    func store(key: MLXArray, value: MLXArray) {
        self.key = key
        self.value = value
    }

    /// What was kept, or a refusal if the first step never ran.
    func read() throws -> (key: MLXArray, value: MLXArray) {
        guard let key, let value else { throw QwenImage21TransformerError.cacheWasNotExtracted }
        return (key, value)
    }

    /// The arrays to evaluate, so the copy actually happens rather than sitting as a graph node
    /// that holds the whole step behind it.
    var held: [MLXArray] { [key, value].compactMap { $0 } }
}
