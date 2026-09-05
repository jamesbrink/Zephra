import Foundation
import MLX
import Testing
import ZephraMLX

@Suite("The pooling and the bytes a preview frame is made of")
struct LatentPreviewTests {
    @Test("a latent already small enough is not pooled at all")
    func smallLatentsAreLeftAlone() {
        #expect(LatentPreview.poolingFactor(height: 16, width: 32) == 1)
        #expect(LatentPreview.poolingFactor(height: 1, width: 1) == 1)
    }

    @Test("the factor is whatever brings the long edge under the limit")
    func theFactorFollowsTheLongEdge() {
        // A 1024-pixel image is 128 latent cells, which is four cells to one.
        #expect(LatentPreview.poolingFactor(height: 128, width: 128) == 4)
        // The long edge decides, so a wide image is not pooled by less than a square one.
        #expect(LatentPreview.poolingFactor(height: 64, width: 160) == 5)
        // 33 cells is one over, and one over is a factor of two rather than of one and a bit.
        #expect(LatentPreview.poolingFactor(height: 33, width: 33) == 2)
    }

    @Test("pooling takes the mean of each block")
    func poolingTakesBlockMeans() {
        // 0 to 15 row-major: the first 2x2 block is 0, 1, 4, 5, whose mean is 2.5.
        let latents = MLXArray((0..<16).map { Float($0) }, [1, 1, 4, 4])
        let pooled = LatentPreview.pooled(latents, by: 2)

        #expect(pooled.shape == [1, 1, 2, 2])
        let expected = MLXArray([Float](arrayLiteral: 2.5, 4.5, 10.5, 12.5), [1, 1, 2, 2])
        #expect(MLX.allClose(pooled, expected, atol: 0).item(Bool.self))
    }

    @Test("a row that does not fill a block is left out rather than half-counted")
    func theRemainderIsDropped() {
        // 5 rows by 3 columns, 0 to 14: two whole blocks down and one across; the fifth row
        // and the third column are never averaged in.
        let latents = MLXArray((0..<15).map { Float($0) }, [1, 1, 5, 3])
        let pooled = LatentPreview.pooled(latents, by: 2)
        #expect(pooled.shape == [1, 1, 2, 1])
        // Blocks {0, 1, 3, 4} and {6, 7, 9, 10}.
        let expected = MLXArray([Float](arrayLiteral: 2, 8), [1, 1, 2, 1])
        #expect(MLX.allClose(pooled, expected, atol: 0).item(Bool.self))
    }

    @Test("the bytes are four to a pixel, opaque, and hold the range the decoder produced")
    func bytesAreRGBA8() {
        // One row of two pixels: -1 in every channel is black, 1 is white.
        let pixels = MLXArray([Float](arrayLiteral: -1, -1, -1, 1, 1, 1), [1, 1, 2, 3])
        let bytes = LatentPreview.rgba8(pixels)

        #expect(bytes.count == 1 * 2 * 4)
        #expect(Array(bytes) == [0, 0, 0, 255, 255, 255, 255, 255])
    }
}
