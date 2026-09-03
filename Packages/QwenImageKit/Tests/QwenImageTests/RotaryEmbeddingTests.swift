import Foundation
import MLX
import MLXRandom
import Testing

@testable import QwenImage

/// Position embedding. This is the piece most able to produce a confident, wrong image: a
/// mistake here leaves every tensor the right shape and every value finite, and only the
/// composition falls apart. So the invariants are asserted directly rather than inferred from a
/// picture looking plausible.
@Suite("Rotary embedding")
struct RotaryEmbeddingTests {
    private static let embedding = QwenImageRotaryEmbedding(theta: 10000, axesDim: [16, 56, 56])

    @Test("a spatial axis is centred on zero, with the extra position on the negative side")
    func centredPositions() {
        #expect(QwenImageRotaryEmbedding.centred(4) == [-2, -1, 0, 1])
        #expect(QwenImageRotaryEmbedding.centred(5) == [-3, -2, -1, 0, 1])
        let sixtyFour = QwenImageRotaryEmbedding.centred(64)
        #expect(sixtyFour.first == -32)
        #expect(sixtyFour.last == 31)
        #expect(sixtyFour.count == 64)
    }

    @Test("the tables are one row per token, half a head wide")
    func tableShapes() {
        let (image, text) = Self.embedding.frequencies(
            frames: 1, height: 64, width: 64, textLength: 20)
        // 16 + 56 + 56 = 128 channels per head, rotated in pairs.
        #expect(image.cos.shape == [4096, 64])
        #expect(image.sin.shape == [4096, 64])
        #expect(text.cos.shape == [20, 64])
        #expect(text.count == 20)
    }

    @Test("text starts past the image, so no text position collides with an image position")
    func textSitsAfterTheImage() {
        // A 64x64 patch grid is centred on zero, so it reaches 31; text starts at 32.
        let (_, text) = Self.embedding.frequencies(
            frames: 1, height: 64, width: 64, textLength: 3)
        let expected = QwenImageRotaryEmbedding(theta: 10000, axesDim: [16, 56, 56])
        let (_, shifted) = expected.frequencies(frames: 1, height: 2, width: 2, textLength: 3)
        // The two differ only because the origin moved, which is the whole point of the offset.
        #expect(!MLX.allClose(text.cos, shifted.cos).item(Bool.self))
    }

    @Test("the frame axis contributes nothing for a still image")
    func singleFrameLeavesItsAxisUnrotated() {
        let (image, _) = Self.embedding.frequencies(
            frames: 1, height: 4, width: 4, textLength: 1)
        // Frame position 0 gives an angle of 0 on all eight of its pairs: cosine one, sine zero.
        let frameCos = image.cos[0..<16, 0..<8]
        let frameSin = image.sin[0..<16, 0..<8]
        #expect(MLX.allClose(frameCos, MLXArray.ones([16, 8])).item(Bool.self))
        #expect(MLX.allClose(frameSin, MLXArray.zeros([16, 8])).item(Bool.self))
    }

    @Test("the centre of the image is the origin, so its angles are zero")
    func centreOfTheImageIsUnrotated() {
        let (image, _) = Self.embedding.frequencies(
            frames: 1, height: 4, width: 4, textLength: 1)
        // Positions run -2, -1, 0, 1, so the token at row 2, column 2 sits at (0, 0).
        let centre = 2 * 4 + 2
        #expect(MLX.allClose(image.cos[centre], MLXArray.ones([64])).item(Bool.self))
        #expect(MLX.allClose(image.sin[centre], MLXArray.zeros([64])).item(Bool.self))
    }

    @Test("rotation preserves the length of every channel pair")
    func rotationIsARotation() {
        let (image, _) = Self.embedding.frequencies(
            frames: 1, height: 4, width: 4, textLength: 1)
        let x = MLXRandom.normal([1, 16, 3, 128])
        let rotated = image.rotate(x)
        #expect(rotated.shape == x.shape)

        // Pair magnitudes are invariant under rotation, whatever the angles are.
        func pairMagnitudes(_ value: MLXArray) -> MLXArray {
            let pairs = value.reshaped([1, 16, 3, 64, 2])
            return MLX.sqrt(MLX.sum(pairs * pairs, axis: -1))
        }
        #expect(
            MLX.allClose(pairMagnitudes(rotated), pairMagnitudes(x), atol: 1e-5)
                .item(Bool.self))
    }

    @Test("rotating by a zero angle is the identity")
    func zeroAngleDoesNothing() {
        let identity = RotaryFrequencies(
            cos: MLXArray.ones([5, 4]), sin: MLXArray.zeros([5, 4]))
        let x = MLXRandom.normal([2, 5, 3, 8])
        #expect(MLX.allClose(identity.rotate(x), x, atol: 1e-6).item(Bool.self))
    }
}
