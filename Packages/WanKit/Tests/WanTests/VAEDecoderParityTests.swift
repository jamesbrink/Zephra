import Foundation
import MLX
import MLXNN
import Testing

@testable import Wan

@Suite("the video decoder reproduces the reference's chunked decode")
struct VAEDecoderParityTests {
    static let dollsHouse = VAEEncoderParityTests.dollsHouse

    @Test("a two-frame latent decodes to the reference's five frames, one chunk a latent frame")
    func decodeMatchesTheReference() throws {
        let fixture = try Fixture.load("vae_decoder")
        let autoencoder = try VAEEncoderParityTests.loaded(fixture)
        #expect(autoencoder.dtype == .float32)

        let latent = try #require(fixture["in.latent"])
        let expected = try #require(fixture["out.video"]).transposed(0, 2, 3, 4, 1)
        let video = autoencoder.decode(latent)
        #expect(video.shape == [1, 5, 64, 64, 3])
        #expect(video.shape == expected.shape)
        // 2 x 4 x 4 cells become 5 x 64 x 64 pixels: 1 + 4 (F' - 1) frames, 16 per cell.
        #expect(Self.dollsHouse.pixelFrames(forLatentFrames: 2) == 5)
        let difference = Fixture.maxAbsoluteDifference(video, expected)
        // Measured at 1.3e-6 on an M4 Max: the clamp pins most pixels and the rest differ by
        // float32 accumulation order over three stages of convolutions.
        #expect(difference < 1e-4, "max abs difference \(difference)")
    }

    @Test("the pixels come back clamped, as the reference's decode clamps them")
    func decodeIsClamped() throws {
        let fixture = try Fixture.load("vae_decoder")
        let autoencoder = try VAEEncoderParityTests.loaded(fixture)
        let video = autoencoder.decode(try #require(fixture["in.latent"]) * 40)
        #expect(video.max().item(Float.self) <= 1)
        #expect(video.min().item(Float.self) >= -1)
    }

    @Test("one latent frame decodes to one frame, the same frame a longer clip begins with")
    func theFirstFrameIsCausal() throws {
        let fixture = try Fixture.load("vae_decoder")
        let autoencoder = try VAEEncoderParityTests.loaded(fixture)
        let latent = try #require(fixture["in.latent"])
        let alone = autoencoder.decode(latent[0..., 0..., 0..<1])
        #expect(alone.shape == [1, 1, 64, 64, 3])
        #expect(Self.dollsHouse.pixelFrames(forLatentFrames: 1) == 1)
        let whole = autoencoder.decode(latent)[0..., 0..<1]
        #expect(Fixture.maxAbsoluteDifference(whole, alone) == 0)
    }

    @Test("the temporal upsampler's two channel halves become the even and the odd frame")
    func interleaveOrder() {
        // Two channels, one frame: channel c·2 + i, where c is the half and i the channel.
        let x = MLXArray((0..<4).map(Float.init), [1, 1, 1, 1, 4])
        let frames = WanResample.interleaved(x)
        #expect(frames.shape == [1, 2, 1, 1, 2])
        #expect(frames[0, 0, 0, 0].asArray(Float.self) == [0, 1])
        #expect(frames[0, 1, 0, 0].asArray(Float.self) == [2, 3])
    }

    @Test("the duplicated-up shortcut drops the frames before the first on the first chunk")
    func firstChunkKeepsOneFrame() {
        let up = WanDupUp3D(inputChannels: 1, outputChannels: 1, temporalFactor: 2, spatialFactor: 2)
        let x = MLXArray([Float(7)], [1, 1, 1, 1, 1])
        #expect(up(x, firstChunk: true).shape == [1, 1, 2, 2, 1])
        #expect(up(x, firstChunk: false).shape == [1, 2, 2, 2, 1])
        #expect(up(x, firstChunk: true).asArray(Float.self) == [7, 7, 7, 7])
    }

    @Test("the unpatchify puts a colour's channels over the column offset first, then the row")
    func unpatchifyOrder() {
        // One 2 x 2 patch of 3 colours: channel c·4 + a·2 + b, `a` the column offset.
        let x = MLXArray((0..<12).map(Float.init), [1, 1, 1, 1, 12])
        let pixels = WanPatchify.unpatchified(x, patch: 2)
        #expect(pixels.shape == [1, 1, 2, 2, 3])
        // Row 1 (b = 1), column 0 (a = 0), colour 2: 2·4 + 0·2 + 1 = 9.
        #expect(pixels[0, 0, 1, 0, 2].item(Float.self) == 9)
        // Row 0 (b = 0), column 1 (a = 1), colour 0: 0·4 + 1·2 + 0 = 2.
        #expect(pixels[0, 0, 0, 1, 0].item(Float.self) == 2)
    }
}
