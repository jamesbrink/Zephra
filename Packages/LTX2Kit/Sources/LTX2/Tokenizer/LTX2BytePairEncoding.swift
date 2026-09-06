import Foundation

/// Gemma's byte-pair encoding, the SentencePiece flavour: spaces become `▁`, the whole text is
/// one word, characters are Unicode scalars, and a scalar the vocabulary lacks becomes its
/// UTF-8 bytes as `<0xNN>` tokens before any merging.
///
/// Written here rather than taken from swift-transformers because that library splits a word
/// into `Character`s, which are grapheme clusters: an emoji joined to another with a zero-width
/// joiner is one `Character` and not in any vocabulary, so it fell back to bytes where the
/// reference finds the scalars' own tokens. The reference tokenizes scalars.
enum LTX2BytePairEncoding {
    /// The ids for one stretch of plain text, no added tokens inside it.
    static func encode(_ text: String, with vocabulary: LTX2TokenizerVocabulary) -> [Int] {
        let normalized = text.replacingOccurrences(of: " ", with: "\u{2581}")
        var symbols: [Int] = []
        symbols.reserveCapacity(normalized.unicodeScalars.count)
        for scalar in normalized.unicodeScalars {
            if let id = vocabulary.id(of: String(scalar)) {
                symbols.append(id)
            } else {
                symbols += String(scalar).utf8.map { vocabulary.byteTokens[Int($0)] }
            }
        }
        return merged(symbols, with: vocabulary)
    }

    /// Applies the merge rules by rank: at each step the adjacent pair with the lowest rank is
    /// joined everywhere it occurs, left to right, until no pair has a rule.
    static func merged(_ symbols: [Int], with vocabulary: LTX2TokenizerVocabulary) -> [Int] {
        var word = symbols
        while word.count > 1 {
            var best: (rank: Int, id: Int, pair: LTX2TokenizerVocabulary.Pair)?
            for index in 0..<(word.count - 1) {
                let pair = LTX2TokenizerVocabulary.Pair(first: word[index], second: word[index + 1])
                if let rule = vocabulary.merges[pair], rule.rank < (best?.rank ?? .max) {
                    best = (rule.rank, rule.id, pair)
                }
            }
            guard let best else { break }
            var joined: [Int] = []
            joined.reserveCapacity(word.count)
            var index = 0
            while index < word.count {
                if index + 1 < word.count, word[index] == best.pair.first, word[index + 1] == best.pair.second {
                    joined.append(best.id)
                    index += 2
                } else {
                    joined.append(word[index])
                    index += 1
                }
            }
            word = joined
        }
        return word
    }
}
