import Foundation
import MLX
import Testing

@testable import Flux2

/// The mask the reference builds for a right-padded batch of one, drawn out and compared.
///
/// This is checked directly, not just through the encoder's output, because it is the piece
/// most easily got subtly wrong: a mask that hides the padding from itself as well would leave
/// the padded positions attending to nothing, and klein feeds those positions to the
/// transformer.
@Suite("The Qwen3 attention mask hides the future and the padding")
struct AttentionMaskTests {
    @Test("a key is blocked when it is in the query's future or is padding, and otherwise not")
    func blocksTheFutureAndThePadding() {
        let mask = Qwen3AttentionMask.causalAndPadding(length: 12, validCount: 7, dtype: .float32)
        #expect(mask.shape == [1, 1, 12, 12])

        let values = mask.asArray(Float.self)
        let drawn = (0..<12).map { row in
            String((0..<12).map { values[row * 12 + $0] < -1e8 ? "x" : "." })
        }
        // The same pattern `transformers` builds, confirmed against `create_causal_mask` for
        // this exact input: seven real tokens, five pad ids, one row per query.
        let expected = (0..<12).map { row in
            String((0..<12).map { ($0 > row || $0 >= 7) ? "x" : "." })
        }
        #expect(drawn == expected, Comment(rawValue: drawn.joined(separator: "\n")))
    }

    @Test("every blocked score is finite, and no row is blocked all the way across")
    func staysFiniteAndLeavesEveryRowSomethingToAttendTo() {
        let mask = Qwen3AttentionMask.causalAndPadding(length: 12, validCount: 7, dtype: .float32)
        let values = mask.asArray(Float.self)

        let finite = values.allSatisfy { $0.isFinite }
        #expect(finite)
        let open = (0..<12).map { row in (0..<12).contains { values[row * 12 + $0] == 0 } }
        let everyRowOpen = open.allSatisfy { $0 }
        #expect(everyRowOpen)
    }

    @Test("a sequence with no padding is masked by causality alone")
    func noPaddingLeavesTheCausalTriangle() {
        let mask = Qwen3AttentionMask.causalAndPadding(length: 5, validCount: 5, dtype: .float32)
        let values = mask.asArray(Float.self)
        let open = (0..<5).map { row in (0..<5).filter { values[row * 5 + $0] == 0 } }
        #expect(open == [[0], [0, 1], [0, 1, 2], [0, 1, 2, 3], [0, 1, 2, 3, 4]])
    }
}
