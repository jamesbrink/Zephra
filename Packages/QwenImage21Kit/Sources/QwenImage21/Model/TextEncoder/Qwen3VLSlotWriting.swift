import Foundation
import MLX

/// Writing the tower's rows into a prompt at the picture's token slots, the two ways the
/// reference does it.
///
/// `masked_scatter` puts the merged slots over the embedding rows the `<|image_pad|>` tokens
/// produced, before layer 0. `_deepstack_process` **adds** each tap at those same rows, after
/// layers 0, 1 and 2. Both are here because both need the same fact — that a picture's slots
/// are one contiguous run, since the processor expands one `<|image_pad|>` into the whole run —
/// and that fact is what lets each be slicing and concatenation rather than a scatter.
enum Qwen3VLSlotWriting {
    /// `base`, `[1, tokens, hidden]`, with each run's rows replaced by the next rows of `slots`.
    static func replacing(_ base: MLXArray, with slots: MLXArray, runs: [Range<Int>]) -> MLXArray {
        assembled(tokens: base.dim(1), runs: runs) { range, taken in
            slots[taken].expandedDimensions(axis: 0).asType(base.dtype)
        } outside: { range in
            base[0..., range, 0...]
        }
    }

    /// `[1, tokens, hidden]` that is `rows` at the runs and zero everywhere else.
    static func spread(_ rows: MLXArray, runs: [Range<Int>], tokens: Int) -> MLXArray {
        let hidden = rows.dim(-1)
        return assembled(tokens: tokens, runs: runs) { range, taken in
            rows[taken].expandedDimensions(axis: 0).asType(.float32)
        } outside: { range in
            MLXArray.zeros([1, range.count, hidden], type: Float.self)
        }
    }

    /// Walks the sequence once, asking `inside` for each run and `outside` for the gaps.
    ///
    /// `taken` is the run's slice of the rows, which advance across pictures in the order the
    /// runs do, so several references land in the order they were encoded.
    private static func assembled(
        tokens: Int,
        runs: [Range<Int>],
        inside: (Range<Int>, Range<Int>) -> MLXArray,
        outside: (Range<Int>) -> MLXArray
    ) -> MLXArray {
        var pieces: [MLXArray] = []
        var cursor = 0
        var consumed = 0
        for run in runs {
            if run.lowerBound > cursor { pieces.append(outside(cursor..<run.lowerBound)) }
            pieces.append(inside(run, consumed..<(consumed + run.count)))
            cursor = run.upperBound
            consumed += run.count
        }
        if cursor < tokens { pieces.append(outside(cursor..<tokens)) }
        return MLX.concatenated(pieces, axis: 1)
    }
}
