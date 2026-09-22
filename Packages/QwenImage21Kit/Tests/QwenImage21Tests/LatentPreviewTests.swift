import Foundation
import MLX
import Testing
import ZephraMLX

@testable import QwenImage21

@Suite("the latent preview decodes one small RGBA frame")
struct LatentPreviewTests {
    @Test("the long edge is pooled to at most thirty-two cells, and small latents are left alone")
    func pooling() {
        #expect(LatentPreview.poolingFactor(height: 64, width: 64) == 2)
        #expect(LatentPreview.poolingFactor(height: 64, width: 128) == 4)
        #expect(LatentPreview.poolingFactor(height: 32, width: 32) == 1)
        #expect(LatentPreview.poolingFactor(height: 4, width: 6) == 1)
    }

    @Test("a frame is the latent decoded at the pooled size, as RGBA8 with the picture's alpha")
    func frame() throws {
        let fixture = try Fixture.load("vae")
        let autoencoder = try VAEFixture.dollsHouseAutoencoder(fixture)
        let normalization = QwenImage21LatentNormalization(VAEFixture.dollsHouse)
        // 4 x 4 cells need no pooling, and the doll's house is four pixels a cell.
        let latents = VAEFixture.channelsLast(try #require(fixture["out.normalised"]))

        let preview = try QwenImage21LatentPreview.make(
            latents: latents, normalization: normalization, autoencoder: autoencoder)
        #expect(preview.width == 16)
        #expect(preview.height == 16)
        #expect(preview.pixels.count == 16 * 16 * 4)
    }

    @Test("a latent past the cell limit is pooled, so the frame comes back smaller")
    func pooledFrame() throws {
        let fixture = try Fixture.load("vae")
        let autoencoder = try VAEFixture.dollsHouseAutoencoder(fixture)
        let normalization = QwenImage21LatentNormalization(VAEFixture.dollsHouse)
        MLXRandom.seed(3)
        // 68 cells an edge pools by 3 to 22, which at four pixels a cell is 88.
        let latents = MLXRandom.normal([1, 68, 68, VAEFixture.dollsHouse.zDim])

        let preview = try QwenImage21LatentPreview.make(
            latents: latents, normalization: normalization, autoencoder: autoencoder)
        #expect(preview.width == 88)
        #expect(preview.height == 88)
        #expect(preview.pixels.count == 88 * 88 * 4)
    }

    @Test("the frame's alpha is the picture's own, not an opaque column")
    func alphaIsCarried() throws {
        let fixture = try Fixture.load("vae")
        let autoencoder = try VAEFixture.dollsHouseAutoencoder(fixture)
        let normalization = QwenImage21LatentNormalization(VAEFixture.dollsHouse)
        let latents = VAEFixture.channelsLast(try #require(fixture["out.normalised"]))
        let preview = try QwenImage21LatentPreview.make(
            latents: latents, normalization: normalization, autoencoder: autoencoder)

        let alpha = stride(from: 3, to: preview.pixels.count, by: 4).map { preview.pixels[$0] }
        #expect(alpha.contains { $0 != 255 }, "an opaque column would be 255 throughout")
    }
}
