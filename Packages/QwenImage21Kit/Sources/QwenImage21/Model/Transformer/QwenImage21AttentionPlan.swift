import Foundation
import MLX
import MLXFast

/// The attention calls one step makes, decided once and read by all 32 blocks.
///
/// The block-causal structure is several ordinary attention calls rather than one dense mask,
/// which is what lets this run on a fused kernel with no mask at all in the common case. Built
/// once per step because the boundaries depend on the layout and nothing else, and a mask array
/// rebuilt 32 times is 32 allocations of the same numbers.
///
/// Text-to-image with an unpadded prompt is two passes on the first step and one on every step
/// after it. A prompt that was right-padded is the only thing that puts an array mask in any of
/// them, and batch one never pads.
struct QwenImage21AttentionPlan {
    /// One attention call.
    struct Pass {
        /// Which of this step's queries the call covers.
        let queries: Range<Int>
        /// How many keys it attends over, counting from the front, or nil for every key.
        let keyLimit: Int?
        /// What the call masks with.
        let mask: MLXFast.ScaledDotProductAttentionMaskMode
    }

    let passes: [Pass]

    /// The first step: every prefix segment, then the target's own queries over everything.
    static func prefill(
        segments: [QwenImage21AttentionSegments.Segment],
        keyValid: [Bool]?,
        sequenceLength: Int
    ) -> Self {
        var passes = segments.map { segment in
            Pass(
                queries: segment.start..<segment.end,
                keyLimit: segment.end,
                mask: mask(
                    queryCount: segment.end - segment.start, keyCount: segment.end,
                    causal: segment.isText, keyValid: keyValid))
        }
        let target = segments.last?.end ?? 0
        passes.append(
            Pass(
                queries: target..<sequenceLength, keyLimit: nil,
                mask: mask(
                    queryCount: sequenceLength - target, keyCount: sequenceLength,
                    causal: false, keyValid: keyValid)))
        return Self(passes: passes)
    }

    /// Every step after it: the target's queries over the cached prefix and themselves. The
    /// block-causal rule degenerates to full attention for those rows, so only a padded prompt
    /// needs a mask at all.
    static func decode(targetTokens: Int, keyValid: [Bool]?) -> Self {
        Self(
            passes: [
                Pass(
                    queries: 0..<targetTokens, keyLimit: nil,
                    mask: mask(
                        queryCount: targetTokens, keyCount: keyValid?.count ?? 0,
                        causal: false, keyValid: keyValid))
            ])
    }

    /// A causal triangle aligned to the bottom right, the padding mask, both, or neither.
    ///
    /// The reference's text segment carries `[ones(len, start) | tril(len, len)]`, which is
    /// exactly what MLX's own causal mode builds when the keys outnumber the queries — it
    /// offsets the triangle by `keys - queries`. So the common case needs no array.
    private static func mask(
        queryCount: Int, keyCount: Int, causal: Bool, keyValid: [Bool]?
    ) -> MLXFast.ScaledDotProductAttentionMaskMode {
        guard let keyValid else { return causal ? .causal : .none }
        let offset = keyCount - queryCount
        var allowed = [Bool]()
        allowed.reserveCapacity(queryCount * keyCount)
        for query in 0..<queryCount {
            for key in 0..<keyCount {
                allowed.append(keyValid[key] && (!causal || key <= offset + query))
            }
        }
        return .array(MLXArray(allowed, [1, 1, queryCount, keyCount]))
    }
}
