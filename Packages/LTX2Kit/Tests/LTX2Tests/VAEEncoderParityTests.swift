import Foundation
import MLX
import MLXNN
import Testing

@testable import LTX2

@Suite("the video encoder reproduces the reference's encode, statistics included")
struct VAEEncoderParityTests {
    /// The doll's-house layout `Tools/dump_vae.py` builds: the real stage pattern and the real
    /// block counts at a thirty-second of the width, four latent channels.
    static let dollsHouse = LTX2VideoEncoderLayout(
        inputChannels: 3,
        latentChannels: 4,
        stages: [
            .init(channels: 4, blocks: 4), .init(channels: 8, blocks: 6),
            .init(channels: 16, blocks: 4), .init(channels: 32, blocks: 2),
            .init(channels: 32, blocks: 2),
        ],
        strides: LTX2VideoEncoderLayout.ltx25.strides,
        patchSize: 4)

    static func loaded(_ fixture: [String: MLXArray]) throws -> LTX2VideoEncoder {
        let encoder = LTX2VideoEncoder(dollsHouse)
        // The fixture's inputs and outputs sit under the same prefix as the weights.
        try encoder.load(weights: fixture.filter {
            !$0.key.hasPrefix("vae_encoder.in.") && !$0.key.hasPrefix("vae_encoder.out.")
        })
        return encoder
    }

    @Test("a nine-frame clip encodes to the reference's two-frame latent within float32 noise")
    func clipMatchesTheReference() throws {
        let fixture = try Fixture.load("vae_encoder")
        let encoder = try Self.loaded(fixture)
        #expect(encoder.dtype == .float32)

        let pixels = try #require(fixture["vae_encoder.in.pixels.clip"])
        let expected = try #require(fixture["vae_encoder.out.latent.clip"])
        let latent = encoder.encode(pixels)
        #expect(latent.shape == [1, 4, 2, 2, 3])
        #expect(latent.shape == expected.shape)
        // 9 x 64 x 96 pixels become 2 x 2 x 3 latent cells: (F - 1) / 8 + 1 frames, one per 32.
        #expect(Self.dollsHouse.latentFrames(forPixelFrames: 9) == 2)
        #expect(Self.dollsHouse.latentCells(forPixels: 96) == 3)
        let difference = Fixture.maxAbsoluteDifference(latent, expected)
        #expect(difference < 5e-5, "max abs difference \(difference)")
    }

    @Test("one picture encodes to one latent frame, which is what a held first frame is")
    func pictureMatchesTheReference() throws {
        let fixture = try Fixture.load("vae_encoder")
        let encoder = try Self.loaded(fixture)

        let pixels = try #require(fixture["vae_encoder.in.pixels.picture"])
        let expected = try #require(fixture["vae_encoder.out.latent.picture"])
        let latent = encoder.encode(pixels)
        #expect(latent.shape == [1, 4, 1, 2, 3])
        #expect(Self.dollsHouse.latentFrames(forPixelFrames: 1) == 1)
        let difference = Fixture.maxAbsoluteDifference(latent, expected)
        #expect(difference < 5e-5, "max abs difference \(difference)")
    }

    @Test("a tree with the statistics left at the identity encodes something else")
    func statisticsMatter() throws {
        let fixture = try Fixture.load("vae_encoder")
        let encoder = try Self.loaded(fixture)
        let pixels = try #require(fixture["vae_encoder.in.pixels.clip"])
        let expected = try #require(fixture["vae_encoder.out.latent.clip"])
        encoder.statistics.update(parameters: ModuleParameters.unflattened([
            "mean_of_means": MLXArray.zeros([4]), "std_of_means": MLXArray.ones([4]),
        ]))
        #expect(Fixture.maxAbsoluteDifference(encoder.encode(pixels), expected) > 1e-2)
    }

    @Test("the space-to-depth fold is the exact inverse of the decoder's depth-to-space")
    func foldIsTheInverseOfTheShuffle() {
        let stride = LTX2VideoEncoderLayout.Stride(temporal: 2, spatial: 2)
        let x = MLXArray(Array(0..<16).map(Float.init), [1, 1, 1, 1, 16])
        let folded = LTX2SpaceToDepthDownsample.folded(
            LTX2DepthToSpaceUpsample.shuffled(x, stride: stride), stride: stride)
        #expect(folded.shape == x.shape)
        #expect(Fixture.maxAbsoluteDifference(folded, x) == 0)
    }

    @Test("the spatial patchify is the exact inverse of the decoder's unpatchify")
    func patchifyIsTheInverseOfTheUnpatchify() {
        // One pixel of 3 colours and a 2 x 2 patch, the order the reference folds them in.
        let x = MLXArray(Array(0..<12).map(Float.init), [1, 1, 1, 1, 12])
        let pixels = LTX2VideoDecoder.unpatchified(x, patch: 2)
        let patched = LTX2VideoEncoder.patchified(pixels, patch: 2)
        #expect(patched.shape == x.shape)
        #expect(Fixture.maxAbsoluteDifference(patched, x) == 0)
    }
}
