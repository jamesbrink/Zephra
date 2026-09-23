import MLX
import Testing

@testable import QwenImage21

@Suite("A picture is written opaque unless it has a hole")
struct OpacityTests {
    @Test("alpha that only carries the decoder's noise is dropped")
    func noiseIsOpaque() {
        var pixels = MLXArray.zeros([1, 4, 4, 4])
        pixels[.ellipsis, 3] = MLXArray(0.97 as Float)  // 251 of 255
        #expect(QwenImage21Opacity.flattened(pixels).dim(3) == 3)
    }

    @Test("one pixel below the floor keeps every channel")
    func aHoleKeepsAlpha() {
        var pixels = MLXArray.zeros([1, 4, 4, 4])
        pixels[.ellipsis, 3] = MLXArray(1 as Float)
        pixels[0, 2, 1, 3] = MLXArray(-1 as Float)
        #expect(QwenImage21Opacity.flattened(pixels).dim(3) == 4)
    }

    @Test("the floor is 250 of 255")
    func floor() {
        #expect(abs(QwenImage21Opacity.opaqueFloor - 0.9607843) < 1e-6)
    }

    @Test("three channels pass through untouched")
    func rgbPassesThrough() {
        let pixels = MLXArray.zeros([1, 2, 2, 3])
        #expect(QwenImage21Opacity.flattened(pixels).dim(3) == 3)
    }
}
