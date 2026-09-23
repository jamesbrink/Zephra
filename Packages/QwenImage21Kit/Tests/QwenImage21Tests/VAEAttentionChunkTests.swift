import Foundation
import MLX
import MLXRandom
import Testing

@testable import QwenImage21

/// The mid block's attention in chunks of queries is the whole attention, not an approximation
/// of it: each query's softmax reads only its own row of scores.
@Suite("the autoencoder's attention in chunks of queries")
struct VAEAttentionChunkTests {
    @Test("chunks that divide the cells and chunks that do not both match one pass")
    func chunksMatchOnePass() {
        MLXRandom.seed(7)
        let block = QwenImage21VAEAttentionBlock(channels: 16)
        let x = MLXRandom.normal([1, 9, 7, 16])
        let whole = block(x, queryChunk: 63)
        for chunk in [9, 10, 31] {
            let chunked = block(x, queryChunk: chunk)
            #expect(chunked.shape == whole.shape)
            let difference = MLX.abs(chunked - whole).max().item(Float.self)
            #expect(difference < 1e-5, "chunk \(chunk): \(difference)")
        }
    }
}
