import Foundation
import MLX
import Testing
import ZephraCore

@testable import ZephraUpscaleRealESRGAN

@Suite("A picture survives the trip to pixels and back")
struct UpscalePixelBufferTests {
    @Test("a PNG round-trips at the same size and the same pixels")
    func roundTrips() throws {
        // Values on the eighth-bit grid, so the round trip is exact rather than within half a
        // level: what this pins is the layout and the range, not the quantiser.
        var levels: [Float] = []
        for index in 0..<(7 * 5 * 3) {
            levels.append(Float((index * 3) % 256) / 255)
        }
        let original = MLXArray(levels, [1, 7, 5, 3])

        let restored = try UpscalePixelBuffer.pixels(
            from: try UpscalePixelBuffer.png(from: original))

        #expect(restored.shape == [1, 7, 5, 3])
        #expect(restored.alpha == nil, "an opaque picture has no alpha lane")
        #expect(Fixture.maxAbsoluteDifference(restored.rgb, original) == 0)
    }

    @Test("out-of-range pixels are clipped rather than wrapped")
    func clipsRatherThanWraps() throws {
        let extremes = MLXArray([-0.4, 0, 0.5, 1, 1.6, 2] as [Float], [1, 1, 2, 3])

        let restored = try UpscalePixelBuffer.pixels(
            from: try UpscalePixelBuffer.png(from: extremes))

        let expected = MLXArray([0, 0, 0.5019608, 1, 1, 1] as [Float], [1, 1, 2, 3])
        #expect(Fixture.maxAbsoluteDifference(restored.rgb, expected) < 1e-6)
    }

    @Test("a transparent picture keeps its alpha in both directions")
    func transparencySurvivesTheRoundTrip() throws {
        // Four pixels, one per alpha: clear, a third, two thirds, opaque; one colour.
        let colour = MLXArray(
            [Float](arrayLiteral: 0.8, 0.2, 0.4, 0.8, 0.2, 0.4, 0.8, 0.2, 0.4, 0.8, 0.2, 0.4),
            [1, 1, 4, 3])
        let alpha = MLXArray([0, 0.33333334, 0.6666667, 1] as [Float], [1, 1, 4, 1])

        let png = try UpscalePixelBuffer.png(from: colour, alpha)
        let restored = try UpscalePixelBuffer.pixels(from: png)

        let back = try #require(restored.alpha)
        #expect(Fixture.maxAbsoluteDifference(back, alpha) < 1e-6, "the alpha lane is straight")
        // The clear pixel has no colour to recover and reads as the white matte; the other
        // three are the colour that went in, an eighth-bit step of premultiplication aside.
        let seen = restored.rgb[0, 0, 1..<4]
        #expect(Fixture.maxAbsoluteDifference(seen, colour[0, 0, 1..<4]) < 0.01)
        #expect(Fixture.maxAbsoluteDifference(restored.rgb[0, 0, 0..<1], MLXArray(Float(1))) == 0)
    }

    @Test("a picture with no alpha channel is encoded exactly as it always was")
    func opaquePicturesAreUnchanged() throws {
        let original = MLXArray([0.1, 0.5, 0.9] as [Float], [1, 1, 1, 3])

        let png = try UpscalePixelBuffer.png(from: original)

        // Colour type 2, truecolour with no alpha: the byte at offset 25 of every PNG.
        #expect(Array(png)[25] == 2)
        #expect(try UpscalePixelBuffer.png(from: original) == png, "and the same bytes twice")
    }

    @Test("a transparent region is read over white rather than over black")
    func theMatteIsWhite() throws {
        // Read back through the opaque door, which is what every other reference context does.
        let png = try UpscalePixelBuffer.png(
            from: MLXArray([0.8, 0.2, 0.4] as [Float], [1, 1, 1, 3]),
            MLXArray([Float(0)], [1, 1, 1, 1]))

        let restored = try UpscalePixelBuffer.pixels(from: png)

        #expect(
            Fixture.maxAbsoluteDifference(restored.rgb, MLXArray(Float(1))) == 0,
            "a wholly clear pixel reads as white, never as black")
    }

    @Test("bytes that are not a picture are refused")
    func refusesRubbish() {
        #expect(throws: UpscaleError.self) {
            _ = try UpscalePixelBuffer.pixels(from: Data("not a png".utf8))
        }
    }
}
