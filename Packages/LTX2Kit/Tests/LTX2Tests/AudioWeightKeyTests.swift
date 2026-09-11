import Foundation
import MLX
import Testing

@testable import LTX2

@Suite("the real audio files' tensors are exactly the trees' parameters")
struct AudioWeightKeyTests {
    /// Every tensor name and shape in the pack's audio files, read from each file's header on
    /// 2026-09-10 and committed as lists.
    static func published(_ name: String) throws -> [String: [Int]] {
        let url = try #require(Bundle.module.resourceURL?.appending(path: "Fixtures/\(name)_keys.json"))
        return try JSONDecoder().decode([String: [Int]].self, from: Data(contentsOf: url))
    }

    @Test("the decoder's paths and shapes match the audio file's decoder half and statistics")
    func decoderKeys() throws {
        let published = try Self.published("audio_vae")
        let tree = LTX2AudioDecoder(.ltx25).parameters().flattened().reduce(into: [String: [Int]]()) {
            $0[LTX2AudioVAEWeights.checkpointName(of: $1.0)] = $1.1.shape
        }
        let expected = published.filter { !$0.key.hasPrefix(LTX2AudioVAEWeights.encoderPrefix) }
        #expect(Set(tree.keys).subtracting(expected.keys).isEmpty, "\(Set(tree.keys).subtracting(expected.keys).sorted())")
        #expect(Set(expected.keys).subtracting(tree.keys).isEmpty, "\(Set(expected.keys).subtracting(tree.keys).sorted())")
        for (key, shape) in expected { #expect(tree[key] == shape, "\(key)") }
        #expect(published.count == 102)
    }

    @Test("the vocoder's paths and shapes match the vocoder file, its inverse basis left out")
    func vocoderKeys() throws {
        let published = try Self.published("vocoder")
        let tree = LTX2Vocoder().parameters().flattened().reduce(into: [String: [Int]]()) {
            $0[LTX2VocoderWeights.checkpointName(of: $1.0)] = $1.1.shape
        }
        let expected = published.filter { $0.key != LTX2VocoderWeights.unused }
        #expect(Set(tree.keys).subtracting(expected.keys).isEmpty, "\(Set(tree.keys).subtracting(expected.keys).sorted())")
        #expect(Set(expected.keys).subtracting(tree.keys).isEmpty, "\(Set(expected.keys).subtracting(tree.keys).sorted())")
        for (key, shape) in expected { #expect(tree[key] == shape, "\(key)") }
        #expect(published.count == 1227)
    }
}
