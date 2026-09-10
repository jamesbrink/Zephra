import Foundation

/// What `tokenizer.json` holds that encoding needs: every piece with its log-probability, the
/// unknown piece's id, and the added tokens matched before anything else.
///
/// Pieces are keyed by their Unicode scalars and never by `String`. Swift compares strings by
/// canonical equivalence, and a 256k-piece vocabulary holds pairs the standard says are the
/// same text as two pieces with two ids and two scores; a `String` key would keep one of each
/// pair and encode the other as it. Scalars are also what the Viterbi walk steps by, so a
/// piece is looked up by exactly the slice of text it would cover.
struct WanTokenizerVocabulary: Sendable {
    /// One piece of the vocabulary: its id and its log-probability.
    struct Piece {
        let id: Int
        let score: Double
    }

    private let pieces: [[Unicode.Scalar]: Piece]
    /// Id to piece text.
    let tokens: [String]
    /// The id a character no piece covers becomes.
    let unknownID: Int
    /// The lowest log-probability in the vocabulary; an unknown character scores ten below it.
    let minimumScore: Double
    /// The most scalars any piece spans, which bounds the prefix search.
    let longestPiece: Int
    /// Added tokens (`</s>`, `<extra_id_0>`, ...) longest first, so a longer one wins a prefix.
    let added: [(scalars: [Unicode.Scalar], id: Int)]

    /// The piece covering exactly `scalars`.
    func piece(_ scalars: ArraySlice<Unicode.Scalar>) -> Piece? { pieces[Array(scalars)] }

    /// The id of exactly this text, scalar for scalar.
    func id(of text: String) -> Int? { pieces[Array(text.unicodeScalars)]?.id }

    /// Reads the file, refusing one that is not a Unigram model with an unknown piece.
    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let model = json["model"] as? [String: Any],
            model["type"] as? String == "Unigram",
            let unknownID = model["unk_id"] as? Int,
            let vocabulary = model["vocab"] as? NSArray
        else { throw WanTokenizerError.malformed(url, reason: "no Unigram model, unk_id or vocab") }
        var pieces: [[Unicode.Scalar]: Piece] = [:]
        var tokens: [String] = []
        pieces.reserveCapacity(vocabulary.count)
        tokens.reserveCapacity(vocabulary.count)
        var minimumScore = 0.0
        var longestPiece = 0
        for case let entry as NSArray in vocabulary {
            guard entry.count == 2, let text = entry[0] as? String, let score = entry[1] as? Double else {
                throw WanTokenizerError.malformed(url, reason: "vocab entry \(tokens.count) is not [piece, score]")
            }
            let scalars = Array(text.unicodeScalars)
            // The file lists pieces in id order; a duplicate takes the later id, as the reference's
            // map does. The release has none, but 197 pairs that are canonically equivalent.
            pieces[scalars] = Piece(id: tokens.count, score: score)
            tokens.append(text)
            minimumScore = min(minimumScore, score)
            longestPiece = max(longestPiece, scalars.count)
        }
        guard tokens.indices.contains(unknownID) else {
            throw WanTokenizerError.malformed(url, reason: "unk_id \(unknownID) is not a piece")
        }
        self.pieces = pieces
        self.tokens = tokens
        self.unknownID = unknownID
        self.minimumScore = minimumScore
        self.longestPiece = longestPiece

        let addedTokens = (json["added_tokens"] as? [[String: Any]]) ?? []
        added = addedTokens.compactMap { entry in
            guard let text = entry["content"] as? String, let id = entry["id"] as? Int else { return nil }
            return (Array(text.unicodeScalars), id)
        }.sorted { $0.scalars.count > $1.scalars.count }
    }
}
