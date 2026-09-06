import Foundation
import MLX
import Testing

@testable import LTX2

@Suite("the latent preview decodes one small frame")
struct LatentPreviewTests {
    @Test("the long edge is pooled to at most eight cells, and small latents are left alone")
    func pooling() {
        #expect(LTX2LatentPreview.poolingFactor(height: 16, width: 24) == 3)
        #expect(LTX2LatentPreview.poolingFactor(height: 9, width: 16) == 2)
        #expect(LTX2LatentPreview.poolingFactor(height: 8, width: 8) == 1)
        #expect(LTX2LatentPreview.poolingFactor(height: 3, width: 5) == 1)
    }

    @Test("a frame is the first latent frame decoded at the pooled size, as opaque RGBA8")
    func frame() throws {
        let fixture = try Fixture.load("vae_decoder")
        let decoder = try VAEDecoderParityTests.loaded(fixture)
        // 4 latent frames of 9 x 16 cells pool by 2 to 4 x 8, which decodes to 128 x 256.
        let latent = MLXArray.zeros([1, 4, 4, 9, 16])
        let preview = LTX2LatentPreview.make(latent: latent, decoder: decoder)
        #expect(preview.width == 256)
        #expect(preview.height == 128)
        #expect(preview.pixels.count == 256 * 128 * 4)
        #expect(preview.pixels[3] == 255)
    }

    @Test("a frame of a one-frame latent is the same picture the full decode's first frame is")
    func firstFrameAgrees() throws {
        let fixture = try Fixture.load("vae_decoder")
        let decoder = try VAEDecoderParityTests.loaded(fixture)
        let latent = try #require(fixture["vae_decoder.in.latent"])  // [1, 4, 2, 2, 3], no pooling
        let preview = LTX2LatentPreview.make(latent: latent, decoder: decoder)
        let whole = LTX2Frames.video(decoder.decode(latent[0..., 0..., 0..<1]), frameRate: 24)
        #expect(preview.pixels == whole.frame(0))
    }
}
