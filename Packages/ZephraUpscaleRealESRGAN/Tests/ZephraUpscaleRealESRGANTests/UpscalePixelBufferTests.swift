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
        #expect(Fixture.maxAbsoluteDifference(restored, original) == 0)
    }

    @Test("out-of-range pixels are clipped rather than wrapped")
    func clipsRatherThanWraps() throws {
        let extremes = MLXArray([-0.4, 0, 0.5, 1, 1.6, 2] as [Float], [1, 1, 2, 3])

        let restored = try UpscalePixelBuffer.pixels(
            from: try UpscalePixelBuffer.png(from: extremes))

        let expected = MLXArray([0, 0, 0.5019608, 1, 1, 1] as [Float], [1, 1, 2, 3])
        #expect(Fixture.maxAbsoluteDifference(restored, expected) < 1e-6)
    }

    @Test("bytes that are not a picture are refused")
    func refusesRubbish() {
        #expect(throws: UpscaleError.self) {
            _ = try UpscalePixelBuffer.pixels(from: Data("not a png".utf8))
        }
    }
}
