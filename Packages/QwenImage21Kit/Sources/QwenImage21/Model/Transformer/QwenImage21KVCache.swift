import Foundation
import MLX

/// The prefix keys and values of every layer, which is what makes forty steps affordable.
///
/// Under `causal_condition` the text and every condition image modulate from the `t = 0` row,
/// so their activations do not change from step to step. The first step writes them here and
/// every step after it recomputes only the target image's tokens — no text work at all, one
/// attention call a layer over `[prefix ++ target]`.
///
/// The cost is `prefixTokens * heads * headDim * 2 * layers * 2` bytes in bfloat16, which for
/// this model is half a megabyte a prefix token: a prompt is tens of megabytes and a 1024
/// square reference is about two gigabytes. One cache per forward; classifier-free guidance
/// runs two forwards and therefore holds two.
public final class QwenImage21KVCache {
    /// What a step is doing with the cache.
    public enum Mode: Sendable {
        /// The first step: compute the whole joint sequence and keep the prefix.
        case extract
        /// Every step after it: compute the target's tokens over the kept prefix.
        case cached
    }

    let layers: [QwenImage21KVLayerCache]

    /// One cache per layer, empty.
    public init(layers count: Int) {
        layers = (0..<count).map { _ in QwenImage21KVLayerCache() }
    }

    /// Reads what the first step wrote in, so the copies happen there rather than as graph
    /// nodes holding the whole prefill behind them until the second step asks.
    func commit() {
        let held = layers.flatMap(\.held)
        guard !held.isEmpty else { return }
        MLX.eval(held)
    }
}
