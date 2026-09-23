import Foundation
import MLX
import Testing
import ZephraMLX

@testable import QwenImage21

@Suite("the latent preview decodes one small RGBA frame")
struct LatentPreviewTests {
    @Test("the long edge is pooled to at most sixteen cells, and small latents are left alone")
    func pooling() {
        // 1024 square is 64 cells, pooled by 4 to 16: a 256-pixel frame, not the shared
        // limit's 512.
        #expect(QwenImage21LatentPreview.poolingFactor(height: 64, width: 64) == 4)
        #expect(QwenImage21LatentPreview.poolingFactor(height: 64, width: 128) == 8)
        #expect(QwenImage21LatentPreview.poolingFactor(height: 48, width: 48) == 3)
        #expect(QwenImage21LatentPreview.poolingFactor(height: 16, width: 16) == 1)
        #expect(QwenImage21LatentPreview.poolingFactor(height: 4, width: 6) == 1)
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
        // 68 cells an edge pools by 5 to 13, which at four pixels a cell is 52.
        let latents = MLXRandom.normal([1, 68, 68, VAEFixture.dollsHouse.zDim])

        let preview = try QwenImage21LatentPreview.make(
            latents: latents, normalization: normalization, autoencoder: autoencoder)
        #expect(preview.width == 52)
        #expect(preview.height == 52)
        #expect(preview.pixels.count == 52 * 52 * 4)
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

    /// Every fourth byte, which is what `GenerationPreview.hasTransparency` reads.
    private static func alpha(_ preview: QwenImage21LatentPreview) -> [UInt8] {
        stride(from: 3, to: preview.pixels.count, by: 4).map { preview.pixels[$0] }
    }

    /// A 4 x 4 grey picture in -1...1 whose alpha is `alpha` everywhere but one pixel, which
    /// carries `corner`.
    private static func picture(alpha: Float, corner: Float) -> MLXArray {
        var values = [Float]()
        for index in 0..<16 {
            values += [0, 0, 0, index == 0 ? corner : alpha]
        }
        return MLXArray(values, [1, 4, 4, 4])
    }

    @Test("an opaque run's noisy alpha is flattened, so its frame reports no transparency")
    func opaqueNoiseIsFlattened() throws {
        // 252 and 250 of 255: the noise an ordinary prompt's alpha carries.
        let preview = try QwenImage21LatentPreview.frame(
            Self.picture(alpha: 252.0 / 255.0 * 2 - 1, corner: 250.0 / 255.0 * 2 - 1))
        #expect(preview.pixels.count == 4 * 4 * 4)
        #expect(Self.alpha(preview).allSatisfy { $0 == 255 })
    }

    @Test("a frame with a real hole keeps its alpha")
    func aHoleIsKept() throws {
        let preview = try QwenImage21LatentPreview.frame(Self.picture(alpha: 1, corner: -1))
        let alpha = Self.alpha(preview)
        #expect(alpha.first == 0)
        #expect(alpha.dropFirst().allSatisfy { $0 == 255 })
    }
}
