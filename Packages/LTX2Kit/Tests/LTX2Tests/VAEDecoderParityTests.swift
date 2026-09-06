import Foundation
import MLX
import MLXNN
import Testing

@testable import LTX2

@Suite("the video decoder reproduces the reference's decode, statistics included")
struct VAEDecoderParityTests {
    /// The doll's-house layout `Tools/dump_vae.py` builds: the real stage pattern at a
    /// thirty-second of the width, one or two blocks a stage, four latent channels.
    static let dollsHouse = LTX2VideoDecoderLayout(
        latentChannels: 4,
        stages: [
            .init(channels: 32, blocks: 1), .init(channels: 16, blocks: 1),
            .init(channels: 16, blocks: 2), .init(channels: 8, blocks: 1),
            .init(channels: 4, blocks: 1),
        ],
        strides: LTX2VideoDecoderLayout.ltx25.strides,
        patchSize: 4)

    static func loaded(_ fixture: [String: MLXArray]) throws -> LTX2VideoDecoder {
        let decoder = LTX2VideoDecoder(dollsHouse)
        // The fixture's inputs and outputs sit under the same prefix as the weights.
        try decoder.load(weights: fixture.filter {
            !$0.key.hasPrefix("vae_decoder.in.") && !$0.key.hasPrefix("vae_decoder.out.")
        })
        return decoder
    }

    @Test("a normalised latent decodes to the reference's frames within float32 noise")
    func decodeMatchesTheReference() throws {
        let fixture = try Fixture.load("vae_decoder")
        let decoder = try Self.loaded(fixture)
        #expect(decoder.dtype == .float32)

        let latent = try #require(fixture["vae_decoder.in.latent"])
        let expected = try #require(fixture["vae_decoder.out.video"]).transposed(0, 2, 3, 4, 1)
        let video = decoder.decode(latent)
        #expect(video.shape == [1, 9, 64, 96, 3])
        #expect(video.shape == expected.shape)
        // 2 x 2 x 3 latent cells become 9 x 64 x 96 pixels: 8 (F' - 1) + 1 frames, 32 per cell.
        #expect(Self.dollsHouse.frames(forLatentFrames: 2) == 9)
        #expect(Self.dollsHouse.pixels(forLatentCells: 3) == 96)
        let difference = Fixture.maxAbsoluteDifference(video, expected)
        // Measured at 8e-6 on an M4 Max; float32 accumulation order is all that differs.
        #expect(difference < 5e-5, "max abs difference \(difference)")
    }

    @Test("a tree with the statistics left at the identity decodes something else")
    func statisticsMatter() throws {
        let fixture = try Fixture.load("vae_decoder")
        let decoder = try Self.loaded(fixture)
        let latent = try #require(fixture["vae_decoder.in.latent"])
        let expected = try #require(fixture["vae_decoder.out.video"]).transposed(0, 2, 3, 4, 1)
        decoder.statistics.update(parameters: ModuleParameters.unflattened([
            "mean": MLXArray.zeros([4]), "std": MLXArray.ones([4]),
        ]))
        #expect(Fixture.maxAbsoluteDifference(decoder.decode(latent), expected) > 1e-2)
    }

    @Test("the first frame of a one-frame latent decodes to exactly one frame")
    func singleFrame() throws {
        let fixture = try Fixture.load("vae_decoder")
        let decoder = try Self.loaded(fixture)
        let latent = try #require(fixture["vae_decoder.in.latent"])[0..., 0..., 0..<1]
        #expect(decoder.decode(latent).shape == [1, 1, 64, 96, 3])
    }

    @Test("the depth-to-space fold puts time before height before width")
    func shuffleOrder() {
        // Two output channels, factor 2x2x2: channel c·8 + t·4 + h·2 + w.
        let x = MLXArray(Array(0..<16).map(Float.init), [1, 1, 1, 1, 16])
        let shuffled = LTX2DepthToSpaceUpsample.shuffled(x, stride: .init(temporal: 2, spatial: 2))
        #expect(shuffled.shape == [1, 2, 2, 2, 2])
        // Frame 1, row 0, column 1, channel 0 is input channel 0·8 + 1·4 + 0·2 + 1 = 5.
        #expect(shuffled[0, 1, 0, 1, 0].item(Float.self) == 5)
        #expect(shuffled[0, 0, 1, 0, 1].item(Float.self) == 8 + 2)
    }

    @Test("the unpatchify puts a colour's patch channels over width first, then height")
    func unpatchifyOrder() {
        // One pixel of 3 colours and a 2 x 2 patch: channel c·4 + a·2 + b, `a` the width offset.
        let x = MLXArray(Array(0..<12).map(Float.init), [1, 1, 1, 1, 12])
        let pixels = LTX2VideoDecoder.unpatchified(x, patch: 2)
        #expect(pixels.shape == [1, 1, 2, 2, 3])
        // Row 1 (b = 1), column 0 (a = 0), colour 2: 2·4 + 0·2 + 1 = 9.
        #expect(pixels[0, 0, 1, 0, 2].item(Float.self) == 9)
        // Row 0 (b = 0), column 1 (a = 1), colour 0: 0·4 + 1·2 + 0 = 2.
        #expect(pixels[0, 0, 0, 1, 0].item(Float.self) == 2)
    }
}
