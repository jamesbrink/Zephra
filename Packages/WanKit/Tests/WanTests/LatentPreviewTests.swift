import Foundation
import MLX
import Testing

@testable import Wan

@Suite("the latent preview decodes one small frame")
struct LatentPreviewTests {
    @Test("the long edge is pooled to at most sixteen cells, and small latents are left alone")
    func pooling() {
        #expect(WanLatentPreview.poolingFactor(height: 30, width: 52) == 4)
        #expect(WanLatentPreview.poolingFactor(height: 18, width: 32) == 2)
        #expect(WanLatentPreview.poolingFactor(height: 16, width: 16) == 1)
        #expect(WanLatentPreview.poolingFactor(height: 3, width: 5) == 1)
    }

    @Test("a frame is one latent frame decoded at the pooled size, as opaque RGBA8")
    func frame() throws {
        let fixture = try Fixture.load("vae_decoder")
        let autoencoder = try VAEEncoderParityTests.loaded(fixture)
        let normalization = WanLatentNormalization(VAEDecoderParityTests.dollsHouse)
        // 3 latent frames of 4 x 4 cells need no pooling and decode to 64 x 64.
        let latent = try #require(fixture["in.latent"])
        let preview = try WanLatentPreview.make(latent: latent, decoder: autoencoder, normalization: normalization)
        #expect(preview.width == 64)
        #expect(preview.height == 64)
        #expect(preview.pixels.count == 64 * 64 * 4)
        #expect(preview.pixels[3] == 255)
    }

    @Test("frame 1 is that latent frame decoded alone, not frame 0 again")
    func laterFrame() throws {
        let fixture = try Fixture.load("vae_decoder")
        let autoencoder = try VAEEncoderParityTests.loaded(fixture)
        let normalization = WanLatentNormalization(VAEDecoderParityTests.dollsHouse)
        let latent = try #require(fixture["in.latent"])
        let first = try WanLatentPreview.make(latent: latent, decoder: autoencoder, normalization: normalization)
        let second = try WanLatentPreview.make(
            latent: latent, decoder: autoencoder, normalization: normalization, frame: 1)
        #expect(first.pixels != second.pixels)
    }
}
