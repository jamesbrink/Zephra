import Foundation
import MLX
import Testing

@testable import QwenImage

/// Packing latents into patch tokens. A wrong axis order here scrambles the image into
/// convincing noise, so the permutation is pinned against a counter tensor worked out by hand.
@Suite("Latent packing")
struct LatentPackingTests {
    @Test("a 2x2 patch arrives channel-major, then row, then column")
    func packOrdersOneTokenByHand() {
        // Values are c * 16 + h * 4 + w, so every element names its own coordinates.
        let latents = MLXArray(0..<32, [1, 2, 4, 4])
        let packed = QwenImageLatentPacking.pack(latents)
        #expect(packed.shape == [1, 4, 8])

        // The top-left patch holds channel 0's four cells, then channel 1's.
        let firstToken = packed[0, 0].asArray(Int32.self)
        #expect(firstToken == [0, 1, 4, 5, 16, 17, 20, 21])
    }

    @Test("unpacking is the exact inverse of packing")
    func roundTrip() {
        let latents = MLXArray(0..<(2 * 16 * 8 * 6), [2, 16, 8, 6])
        let restored = QwenImageLatentPacking.unpack(
            QwenImageLatentPacking.pack(latents), height: 8, width: 6)
        #expect(restored.shape == latents.shape)
        #expect(MLX.all(restored .== latents).item(Bool.self))
    }

    @Test("a 1024 pixel image is 4096 tokens")
    func tokenCountAtTheDefaultSize() {
        // 1024 pixels, an eightfold VAE, and a 2x2 patch: 128 latent cells become 64 patches.
        #expect(QwenImageLatentPacking.tokenCount(latentHeight: 128, latentWidth: 128) == 4096)
        #expect(QwenImageLatentPacking.tokenCount(latentHeight: 64, latentWidth: 64) == 1024)
    }
}
