import Foundation
import MLX
import Testing

@testable import QwenImage21

@Suite("Packing a latent is a plain spatial flatten, because 2.1 has no patchify")
struct LatentPackingTests {
    @Test("tokens and grid are inverses at both shapes")
    func roundTrip() {
        for (height, width) in [(4, 6), (64, 64)] {
            let channels = 8
            let latents = MLXArray(0..<(channels * height * width))
                .reshaped([1, channels, height, width]).asType(.float32)
            let tokens = QwenImage21LatentPacking.tokens(latents)
            #expect(tokens.shape == [1, height * width, channels])
            let back = QwenImage21LatentPacking.grid(tokens, height: height, width: width)
            #expect(back.shape == latents.shape)
            #expect(Fixture.maxAbsoluteDifference(back, latents) == 0)
        }
    }

    @Test("a token is one latent cell, so the channels survive the flatten unchanged")
    func tokensAreCellsNotPatches() {
        // Values name their coordinates: channel * 100 + row * 10 + column.
        var values: [Float] = []
        for channel in 0..<2 {
            for row in 0..<2 {
                for column in 0..<3 {
                    values.append(Float(channel * 100 + row * 10 + column))
                }
            }
        }
        let latents = MLXArray(values).reshaped([1, 2, 2, 3])
        let tokens = QwenImage21LatentPacking.tokens(latents)
        #expect(tokens.shape == [1, 6, 2])
        // Row-major: token 0 is (row 0, column 0) and carries both channels of that one cell.
        #expect(tokens[0, 0].asArray(Float.self) == [0, 100])
        #expect(tokens[0, 1].asArray(Float.self) == [1, 101])
        #expect(tokens[0, 3].asArray(Float.self) == [10, 110])
        #expect(tokens[0, 5].asArray(Float.self) == [12, 112])
    }

    @Test("the token count is the latent grid itself: 1024 pixels square is 4096 tokens")
    func tokenCounts() {
        #expect(QwenImage21LatentPacking.patchSize == 1)
        #expect(QwenImage21LatentPacking.tokenCount(latentHeight: 64, latentWidth: 64) == 4096)
        #expect(QwenImage21LatentPacking.tokenCount(latentHeight: 128, latentWidth: 128) == 16384)
        #expect(QwenImage21LatentPacking.tokenCount(latentHeight: 32, latentWidth: 32) == 1024)
    }

    @Test("img_shapes lists every condition grid in order and the target last")
    func imageShapes() {
        let shapes = QwenImage21LatentPacking.shapes(
            conditions: [(latentHeight: 32, latentWidth: 48), (latentHeight: 16, latentWidth: 16)],
            target: (latentHeight: 64, latentWidth: 64))
        #expect(shapes.count == 3)
        #expect(shapes[0] == .init(height: 32, width: 48))
        #expect(shapes[1] == .init(height: 16, width: 16))
        #expect(shapes.last == .init(height: 64, width: 64), "the target is last")
        #expect(shapes.allSatisfy { $0.frames == 1 }, "a picture is one frame")
        #expect(shapes.last?.tokenCount == 4096)
    }

    @Test("with no condition images img_shapes is the target alone")
    func imageShapesTextToImage() {
        let shapes = QwenImage21LatentPacking.shapes(
            conditions: [], target: (latentHeight: 64, latentWidth: 64))
        #expect(shapes == [.init(height: 64, width: 64)])
    }
}
