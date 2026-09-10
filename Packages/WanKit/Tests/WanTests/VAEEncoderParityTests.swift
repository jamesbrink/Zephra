import Foundation
import MLX
import MLXNN
import Testing

@testable import Wan

@Suite("the video encoder reproduces the reference's chunked encode")
struct VAEEncoderParityTests {
    /// The doll's house `Tools/dump_vae.py` builds: the real stage pattern at a twentieth of
    /// the width, one block a stage, four latent channels, and the real config's first four
    /// statistics.
    static let dollsHouse = WanVAEConfiguration(
        baseDim: 8, decoderBaseDim: 8, dimMult: [1, 1, 2, 2], numResBlocks: 1,
        temporalDownsample: [false, true, true], zDim: 4, inChannels: 12, outChannels: 12, patchSize: 2,
        latentsMean: Array(WanVAEConfiguration.wan22.latentsMean.prefix(4)),
        latentsStd: Array(WanVAEConfiguration.wan22.latentsStd.prefix(4)))

    /// An autoencoder with one half filled from a fixture; the other half stays random and
    /// unused, so the fixture is checked for landing every tensor but not for covering the tree.
    static func loaded(_ fixture: [String: MLXArray]) throws -> WanVideoAutoencoder {
        let autoencoder = WanVideoAutoencoder(dollsHouse)
        try autoencoder.update(
            parameters: ModuleParameters.unflattened(WanVAEWeights.sanitized(Fixture.weights(fixture, under: ""))),
            verify: [.noUnusedKeys, .shapeMismatch])
        return autoencoder
    }

    @Test("a nine-frame clip encodes to the reference's three-frame latent, three chunks with the cache carried between")
    func clipMatchesTheReference() throws {
        let fixture = try Fixture.load("vae_encoder")
        let autoencoder = try Self.loaded(fixture)
        #expect(autoencoder.dtype == .float32)

        let video = try #require(fixture["in.video"])
        let expected = try #require(fixture["out.latent"])
        let latent = autoencoder.encode(video)
        #expect(latent.shape == [1, 4, 3, 4, 4])
        #expect(latent.shape == expected.shape)
        // 9 x 64 x 64 pixels become 3 x 4 x 4 cells: 1 + (F - 1) / 4 frames, one cell per 16.
        // Three chunks, so the third is carried into from a chunk that was itself carried
        // into, which is the rule every later chunk of a clip follows.
        #expect(Self.dollsHouse.latentFrames(forPixelFrames: 9) == 3)
        #expect(Self.dollsHouse.spatialCompression == 16)
        let difference = Fixture.maxAbsoluteDifference(latent, expected)
        // Measured at 1.5e-7 on an M4 Max; float32 accumulation order is all that differs.
        #expect(difference < 1e-4, "max abs difference \(difference)")
    }

    @Test("one picture encodes to one latent frame, which is what a held first frame is")
    func pictureMatchesTheReference() throws {
        let fixture = try Fixture.load("vae_encoder")
        let autoencoder = try Self.loaded(fixture)

        let picture = try #require(fixture["in.picture"])
        let expected = try #require(fixture["out.picture_latent"])
        let latent = autoencoder.encode(picture)
        #expect(latent.shape == [1, 4, 1, 4, 4])
        #expect(Self.dollsHouse.latentFrames(forPixelFrames: 1) == 1)
        let difference = Fixture.maxAbsoluteDifference(latent, expected)
        // Measured at 1.8e-7 on an M4 Max.
        #expect(difference < 1e-4, "max abs difference \(difference)")
    }

    @Test("the first latent frame reads nothing after the first pixel frame")
    func theFirstFrameIsCausal() throws {
        let fixture = try Fixture.load("vae_encoder")
        let autoencoder = try Self.loaded(fixture)
        let video = try #require(fixture["in.video"])
        let whole = autoencoder.encode(video)[0..., 0..., 0..<1]
        let alone = autoencoder.encode(video[0..., 0..., 0..<1])
        #expect(Fixture.maxAbsoluteDifference(whole, alone) == 0)
    }

    @Test("the patchify puts a colour's channels over the column offset first, then the row")
    func patchifyOrder() {
        // One 2 x 2 patch of 3 colours: pixel (row b, column a, colour c) is c·4 + a·2 + b.
        let pixels = MLXArray(
            (0..<12).map { index -> Float in
                let (row, column, colour) = (index / 6, index / 3 % 2, index % 3)
                return Float(colour * 4 + column * 2 + row)
            }, [1, 1, 2, 2, 3])
        let patched = WanPatchify.patchified(pixels, patch: 2)
        #expect(patched.shape == [1, 1, 1, 1, 12])
        #expect(patched[0, 0, 0, 0].asArray(Float.self) == (0..<12).map(Float.init))
        #expect(Fixture.maxAbsoluteDifference(WanPatchify.unpatchified(patched, patch: 2), pixels) == 0)
    }

    @Test("the averaged-down shortcut is the exact inverse of the duplicated-up one")
    func averageUndoesDuplication() {
        let up = WanDupUp3D(inputChannels: 3, outputChannels: 3, temporalFactor: 2, spatialFactor: 2)
        let down = WanAvgDown3D(inputChannels: 3, outputChannels: 3, temporalFactor: 2, spatialFactor: 2)
        let x = MLXArray((0..<24).map(Float.init), [1, 2, 2, 2, 3])
        let stretched = up(x, firstChunk: false)
        #expect(stretched.shape == [1, 4, 4, 4, 3])
        #expect(Fixture.maxAbsoluteDifference(down(stretched), x) == 0)
        // Averaging groups of eight: input channel c's eight copies all became output channel c.
        #expect(up.repeats == 8)
        #expect(down.groupSize == 8)
    }

    @Test("a temporal halving pads a lone first frame with a zero frame in front")
    func lonelyFramePairsWithZeros() {
        let down = WanAvgDown3D(inputChannels: 1, outputChannels: 2, temporalFactor: 2, spatialFactor: 1)
        let x = MLXArray([Float(4)], [1, 1, 1, 1, 1])
        // Output channel 0 is the time offset 0, the zero frame; channel 1 is the frame itself.
        #expect(down(x).asArray(Float.self) == [0, 4])
    }
}
