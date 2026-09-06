import Foundation
import MLX
import Testing

@testable import LTX2

@Suite("the real decoder's tensors are exactly the tree's parameters")
struct VAEWeightKeyTests {
    /// Every tensor name and shape in `vae_decoder.safetensors` of `mlx-community/ltx-2.5-mlx`,
    /// read from the file's header on 2026-09-06 and committed as a list rather than as
    /// weights, so the layout is pinned without a gigabyte in the repository.
    static func published() throws -> [String: [Int]] {
        let url = try #require(
            Bundle.module.resourceURL?.appending(path: "Fixtures/vae_decoder_keys.json"))
        return try JSONDecoder().decode([String: [Int]].self, from: Data(contentsOf: url))
    }

    @Test("the ltx25 layout's parameter paths and shapes match the published header exactly")
    func keysAndShapes() throws {
        let published = try Self.published()
        let tree = LTX2VideoDecoder(.ltx25).parameters().flattened().reduce(into: [String: [Int]]()) {
            $0[LTX2VAEWeights.prefix + $1.0] = $1.1.shape
        }
        #expect(Set(tree.keys) == Set(published.keys))
        #expect(Set(tree.keys).subtracting(published.keys).isEmpty)
        #expect(Set(published.keys).subtracting(tree.keys).isEmpty)
        for (key, shape) in published {
            #expect(tree[key] == shape, "\(key)")
        }
        #expect(published.count == 86)
    }

    @Test("the layout's arithmetic gives the eight-times-plus-one frames and 32 pixels a cell")
    func growth() {
        let layout = LTX2VideoDecoderLayout.ltx25
        #expect(layout.frames(forLatentFrames: 1) == 1)
        #expect(layout.frames(forLatentFrames: 7) == 49)
        #expect(layout.frames(forLatentFrames: 16) == 121)
        #expect(layout.pixels(forLatentCells: 24) == 768)
        #expect(layout.pixels(forLatentCells: 16) == 512)
    }
}
