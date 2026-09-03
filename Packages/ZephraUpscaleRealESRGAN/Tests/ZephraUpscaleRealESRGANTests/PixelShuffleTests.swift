import Foundation
import MLX
import Testing

@testable import ZephraUpscaleRealESRGAN

@Suite("Channels become pixels in torch's order, and the residual replicates them")
struct PixelShuffleTests {
    @Test("pixel shuffle matches torch's channel-major, row, column ordering")
    func matchesTorch() throws {
        let fixture = try Fixture.load("pixel_shuffle")
        // The fixture's values are an arange, so every element names its own coordinate and a
        // wrong ordering permutes distinct integers rather than moving them slightly.
        let source = Fixture.channelsLast(try #require(fixture["in.source"]))
        let expected = Fixture.channelsLast(try #require(fixture["out.shuffled"]))

        let shuffled = PixelShuffle.apply(source, factor: 2)

        #expect(shuffled.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(shuffled, expected) == 0)
    }

    @Test("a nearest upsample repeats each pixel over its own block")
    func replicates() {
        let source = MLXArray(Array(0..<6).map { Float($0) }, [1, 2, 3, 1])

        let enlarged = NearestUpsample.apply(source, factor: 2)

        #expect(enlarged.shape == [1, 4, 6, 1])
        let expected = MLXArray(
            [
                0, 0, 1, 1, 2, 2,
                0, 0, 1, 1, 2, 2,
                3, 3, 4, 4, 5, 5,
                3, 3, 4, 4, 5, 5,
            ].map { Float($0) }, [1, 4, 6, 1])
        #expect(Fixture.maxAbsoluteDifference(enlarged, expected) == 0)
    }
}
