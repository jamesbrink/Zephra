import Foundation

/// What `tokenizer.json` holds that encoding needs: the vocabulary, the merges by rank, the
/// added tokens matched before anything else, and the 256 byte tokens unknown characters fall
/// back to.
///
/// Tokens are keyed by their UTF-8 bytes and never by `String`. Swift compares strings by
/// canonical equivalence, and Gemma's vocabulary holds pairs the standard says are the same
/// text -- `;` and the Greek question mark, for one -- as two tokens with two ids. A `String`
/// key, in a Swift dictionary or through Foundation's bridging, keeps one of each pair and
/// tokenizes the other as it.
struct LTX2TokenizerVocabulary {
    /// A pair of adjacent symbols, by id, that a merge rule may join.
    struct Pair: Hashable {
        let first: Int
        let second: Int
    }

    /// Token bytes to id.
    private let ids: [[UInt8]: Int]
    /// Id to token string.
    let tokens: [Int: String]
    /// Each merge rule's rank (lower merges first) and the id of the joined token.
    let merges: [Pair: (rank: Int, id: Int)]
    /// Added tokens (`<bos>`, `<|image|>`, ...) longest first, so a longer one wins a prefix.
    let added: [(text: String, id: Int)]
    /// The id of `<0xNN>` for each byte value, for characters the vocabulary has not got.
    let byteTokens: [Int]

    /// The id of exactly this text, byte for byte.
    func id(of text: String) -> Int? { ids[Array(text.utf8)] }

    /// Reads the file, refusing one that lacks any of the four pieces.
    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        // The vocabulary is walked as an `NSDictionary` on purpose: bridging it to a Swift
        // dictionary would merge the canonically equivalent keys described above.
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let model = json["model"] as? [String: Any],
            let vocab = model["vocab"] as? NSDictionary,
            let mergeList = model["merges"] as? [Any]
        else { throw LTX2TokenizerError.malformed(url, reason: "no BPE model, vocab or merges") }
        var byBytes: [[UInt8]: Int] = [:]
        var byId: [Int: String] = [:]
        byBytes.reserveCapacity(vocab.count)
        byId.reserveCapacity(vocab.count)
        for case (let key as String, let id as Int) in vocab {
            byBytes[Array(key.utf8)] = id
            byId[id] = key
        }
        ids = byBytes
        tokens = byId

        var ranked: [Pair: (rank: Int, id: Int)] = [:]
        ranked.reserveCapacity(mergeList.count)
        for (rank, entry) in mergeList.enumerated() {
            let parts: [String]
            if let pair = entry as? [String], pair.count == 2 {
                parts = pair
            } else if let line = entry as? String, let space = line.firstIndex(of: " ") {
                parts = [String(line[..<space]), String(line[line.index(after: space)...])]
            } else {
                throw LTX2TokenizerError.malformed(url, reason: "merge \(rank) is neither a pair nor 'a b'")
            }
            guard let first = byBytes[Array(parts[0].utf8)], let second = byBytes[Array(parts[1].utf8)],
                let joined = byBytes[Array(parts[0].utf8) + Array(parts[1].utf8)]
            else { continue }
            ranked[Pair(first: first, second: second)] = (rank, joined)
        }
        merges = ranked

        let addedTokens = (json["added_tokens"] as? [[String: Any]]) ?? []
        added = addedTokens.compactMap { entry in
            guard let text = entry["content"] as? String, let id = entry["id"] as? Int else { return nil }
            return (text, id)
        }.sorted { $0.text.count > $1.text.count }

        byteTokens = try (0..<256).map { value in
            guard let id = byBytes[Array(String(format: "<0x%02X>", value).utf8)] else {
                throw LTX2TokenizerError.malformed(url, reason: "no byte token for 0x\(String(value, radix: 16))")
            }
            return id
        }
    }
}
