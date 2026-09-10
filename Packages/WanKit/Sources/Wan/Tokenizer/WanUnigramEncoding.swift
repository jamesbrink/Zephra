import Foundation

/// SentencePiece's Unigram segmentation: the split of a piece of text into vocabulary pieces
/// whose log-probabilities sum highest, found by a Viterbi walk over the scalars.
///
/// Written here rather than taken from swift-transformers because the reference this port
/// follows is not the file's own pipeline: `transformers` 5.16.1's `T5Tokenizer` builds its
/// backend from the vocabulary alone, and the fixture pins what that produces. The walk is
/// the reference's, `tokenizers`' optimized lattice: at each start, every piece that begins
/// there proposes its end with the score so far plus its own, a strictly better score takes
/// the node, and a character no single-scalar piece covers proposes an unknown node one
/// scalar long at ten below the vocabulary's lowest score. Unknown nodes next to each other
/// fuse into one `<unk>` on the way back, as `fuse_unk` does.
enum WanUnigramEncoding {
    /// The best path's node ending at a position: where it started, its piece, its score so far.
    private struct Node {
        var start = -1
        var id = -1
        var score = -Double.infinity
    }

    /// The ids for one stretch of text, no added tokens or whitespace inside it.
    static func encode(_ text: [Unicode.Scalar], with vocabulary: WanTokenizerVocabulary) -> [Int] {
        guard !text.isEmpty else { return [] }
        let unknownScore = vocabulary.minimumScore - 10
        var best = [Node](repeating: Node(), count: text.count + 1)
        best[0].score = 0
        for start in 0..<text.count {
            let sofar = best[start].score
            var coveredOneScalar = false
            for end in (start + 1)...min(text.count, start + vocabulary.longestPiece) {
                guard let piece = vocabulary.piece(text[start..<end]) else { continue }
                if end == start + 1 { coveredOneScalar = true }
                let candidate = sofar + piece.score
                if best[end].start < 0 || candidate > best[end].score {
                    best[end] = Node(start: start, id: piece.id, score: candidate)
                }
            }
            if !coveredOneScalar {
                let candidate = sofar + unknownScore
                if best[start + 1].start < 0 || candidate > best[start + 1].score {
                    best[start + 1] = Node(start: start, id: vocabulary.unknownID, score: candidate)
                }
            }
        }
        var ids: [Int] = []
        var end = text.count
        while end > 0 {
            let node = best[end]
            if node.id != vocabulary.unknownID || ids.last != vocabulary.unknownID {
                ids.append(node.id)
            }
            end = node.start
        }
        return ids.reversed()
    }
}
