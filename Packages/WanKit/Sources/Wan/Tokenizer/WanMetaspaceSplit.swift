import Foundation

/// The reference's pre-tokenization: split on whitespace, then mark each word's start with
/// `▁` and split again wherever one appears.
///
/// `transformers` 5.16.1's `T5Tokenizer` puts a `WhitespaceSplit` before the Metaspace step
/// and reads no normalizer at all, so a run of any Unicode whitespace, a newline, a tab or a
/// no-break space, is one word boundary and vanishes; that is what the fixture pins, and it is
/// not what the release's `tokenizer.json` describes on its own. Every word then gets a `▁`
/// in front unless it already begins with one, and is cut before every further `▁`, each cut
/// keeping the `▁` with the text after it, which is the pre-tokenizer's "merged with next".
enum WanMetaspaceSplit {
    /// The word marker, U+2581.
    static let marker: Unicode.Scalar = "\u{2581}"

    /// The pieces of `text` the Unigram model segments one at a time.
    static func pieces(of text: ArraySlice<Unicode.Scalar>) -> [[Unicode.Scalar]] {
        var pieces: [[Unicode.Scalar]] = []
        var word: [Unicode.Scalar] = []
        for scalar in text {
            if isWhitespace(scalar) {
                if !word.isEmpty { pieces += split(word); word.removeAll() }
            } else {
                word.append(scalar)
            }
        }
        if !word.isEmpty { pieces += split(word) }
        return pieces
    }

    /// Rust's `\s`: Unicode `White_Space`, which is what the reference splits on.
    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace
    }

    /// One word marked and cut at every `▁`.
    private static func split(_ word: [Unicode.Scalar]) -> [[Unicode.Scalar]] {
        let marked = word.first == marker ? word : [marker] + word
        var pieces: [[Unicode.Scalar]] = []
        var piece: [Unicode.Scalar] = []
        for scalar in marked {
            if scalar == marker, !piece.isEmpty { pieces.append(piece); piece.removeAll() }
            piece.append(scalar)
        }
        pieces.append(piece)
        return pieces
    }
}
