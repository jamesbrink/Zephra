import Foundation
import MLX
import Testing

@testable import Flux2

@Suite("Latent packing matches the reference's patchify and flatten exactly")
struct LatentPackingTests {
    @Test("patchify and unpatchify are the reference's, cell for cell")
    func patchifyMatchesReference() throws {
        let fixture = try Fixture.load("patchify")
        let latent = try #require(fixture["latent"])
        let packed = try #require(fixture["packed"])
        let tokens = try #require(fixture["tokens"])

        let ours = Flux2LatentPacking.patchify(latent)
        #expect(ours.shape == packed.shape)
        #expect(Fixture.maxAbsoluteDifference(ours, packed) == 0)

        let flattened = Flux2LatentPacking.tokens(ours)
        #expect(flattened.shape == tokens.shape)
        #expect(Fixture.maxAbsoluteDifference(flattened, tokens) == 0)

        let restored = Flux2LatentPacking.unpatchify(
            Flux2LatentPacking.grid(flattened, height: packed.dim(2), width: packed.dim(3)))
        #expect(restored.shape == latent.shape)
        #expect(Fixture.maxAbsoluteDifference(restored, latent) == 0)
    }

    @Test("the top-left token of a coordinate-valued latent holds the cells the layout implies")
    func firstTokenIsChannelMajor() {
        // Values name their coordinates, so the packed channel order can be read off.
        let latent = MLXArray(0..<(1 * 2 * 4 * 4)).asType(.float32).reshaped([1, 2, 4, 4])
        let packed = Flux2LatentPacking.tokens(Flux2LatentPacking.patchify(latent))
        let first = packed[0, 0].asArray(Float.self)
        // Channel 0's 2x2 patch, then channel 1's: c*16 + row*4 + column.
        #expect(first == [0, 1, 4, 5, 16, 17, 20, 21])
    }

    @Test("token count is the patch grid's area")
    func tokenCount() {
        #expect(Flux2LatentPacking.tokenCount(latentHeight: 128, latentWidth: 128) == 4096)
        #expect(Flux2LatentPacking.tokenCount(latentHeight: 64, latentWidth: 96) == 1536)
    }
}
