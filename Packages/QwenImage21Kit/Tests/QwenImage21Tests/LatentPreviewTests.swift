import Foundation
import MLX
import Testing
import ZephraMLX

@testable import QwenImage21

@Suite("the latent preview decodes one RGBA frame at the run's size and shrinks it after")
struct LatentPreviewTests {
    @Test("a latent up to sixty-four cells an edge is decoded whole, and only the 2K sizes pool")
    func pooling() {
        // 1024 square is 64 cells and is not pooled: pooling this latent smears the picture,
        // and a frame pooled four to one stopped changing after the first few steps.
        #expect(QwenImage21LatentPreview.poolingFactor(height: 64, width: 64) == 1)
        #expect(QwenImage21LatentPreview.poolingFactor(height: 48, width: 84) == 2)
        #expect(QwenImage21LatentPreview.poolingFactor(height: 64, width: 128) == 2)
        #expect(QwenImage21LatentPreview.poolingFactor(height: 112, width: 150) == 3)
        #expect(QwenImage21LatentPreview.poolingFactor(height: 16, width: 16) == 1)
        #expect(QwenImage21LatentPreview.poolingFactor(height: 4, width: 6) == 1)
    }

    @Test("the decoded picture is shrunk to at most 512 pixels an edge")
    func pixelPooling() {
        #expect(QwenImage21LatentPreview.pixelPoolingFactor(height: 1024, width: 1024) == 2)
        #expect(QwenImage21LatentPreview.pixelPoolingFactor(height: 768, width: 1344) == 3)
        #expect(QwenImage21LatentPreview.pixelPoolingFactor(height: 512, width: 512) == 1)
        #expect(QwenImage21LatentPreview.pixelPoolingFactor(height: 16, width: 16) == 1)
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

    @Test("a latent past the cell limit is pooled before the decode, so the frame comes back smaller")
    func pooledFrame() throws {
        let fixture = try Fixture.load("vae")
        let autoencoder = try VAEFixture.dollsHouseAutoencoder(fixture)
        let normalization = QwenImage21LatentNormalization(VAEFixture.dollsHouse)
        MLXRandom.seed(3)
        // 68 cells an edge pools by 2 to 34, which at four pixels a cell is 136.
        let latents = MLXRandom.normal([1, 68, 68, VAEFixture.dollsHouse.zDim])

        let preview = try QwenImage21LatentPreview.make(
            latents: latents, normalization: normalization, autoencoder: autoencoder)
        #expect(preview.width == 136)
        #expect(preview.height == 136)
        #expect(preview.pixels.count == 136 * 136 * 4)
    }

    @Test("a picture decoded past the pixel limit is shrunk after the decode, not before")
    func shrunkFrame() throws {
        let fixture = try Fixture.load("vae")
        let autoencoder = try VAEFixture.dollsHouseAutoencoder(fixture)
        let normalization = QwenImage21LatentNormalization(VAEFixture.dollsHouse)
        MLXRandom.seed(4)
        // The doll's house is four pixels a cell, so 32 cells decode to 128 pixels and are
        // not shrunk; a fixture with a real 16-pixel cell would shrink at 33 cells. The rule is
        // pinned on the pure factor above and here on the frame being the decode's own size.
        let latents = MLXRandom.normal([1, 32, 32, VAEFixture.dollsHouse.zDim])

        let preview = try QwenImage21LatentPreview.make(
            latents: latents, normalization: normalization, autoencoder: autoencoder)
        let whole = autoencoder.decodeUntiled(normalization.denormalize(latents))
        #expect(preview.width == whole.dim(2))
        #expect(preview.height == whole.dim(1))
    }

    @Test("a frame is decoded in the run's own tile, so it never peaks above the picture")
    func tiledFrame() throws {
        let fixture = try Fixture.load("vae")
        let autoencoder = try VAEFixture.dollsHouseAutoencoder(fixture)
        let normalization = QwenImage21LatentNormalization(VAEFixture.dollsHouse)
        let latents = VAEFixture.channelsLast(try #require(fixture["out.normalised"]))  // 4 x 4

        let tiled = try QwenImage21LatentPreview.make(
            latents: latents, normalization: normalization, autoencoder: autoencoder, tile: 2)
        let expected = try QwenImage21LatentPreview.frame(
            autoencoder.decode(normalization.denormalize(latents), tile: 2))
        let whole = try QwenImage21LatentPreview.make(
            latents: latents, normalization: normalization, autoencoder: autoencoder)
        #expect(tiled.pixels == expected.pixels)
        #expect(tiled.pixels != whole.pixels, "a two-cell tile of a four-cell latent is an approximation")
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
