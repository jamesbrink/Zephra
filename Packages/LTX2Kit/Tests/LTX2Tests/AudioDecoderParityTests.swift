import Foundation
import MLX
import Testing

@testable import LTX2

@Suite("the audio decoder reproduces the reference's mel, statistics included")
struct AudioDecoderParityTests {
    /// The doll's house `Tools/dump_audio.py` builds: the real three levels and three blocks
    /// at a base of eight, four latent channels over two latent bins.
    static let dollsHouse = LTX2AudioDecoderLayout(
        latentChannels: 4, latentMelBins: 2, baseChannels: 8, multipliers: [1, 2, 4],
        blocksPerLevel: 3, outputChannels: 2, temporalFactor: 4, normEpsilon: 1e-6)

    static func loaded(_ fixture: [String: MLXArray]) throws -> LTX2AudioDecoder {
        let decoder = LTX2AudioDecoder(dollsHouse)
        try decoder.load(weights: fixture.filter { !$0.key.hasPrefix("in.") && !$0.key.hasPrefix("out.") })
        return decoder
    }

    @Test("packed tokens unpack to the reference's latent, denormalised")
    func unpackMatches() throws {
        let fixture = try Fixture.load("audio_decoder")
        let decoder = try Self.loaded(fixture)
        let latent = decoder.unpacked(try #require(fixture["in.tokens"]))
        // The reference holds `[1, C, L, M]`; the tree holds `[1, L, M, C]`.
        let expected = try #require(fixture["in.latent"]).transposed(0, 2, 3, 1)
        #expect(latent.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(latent, expected) < 1e-5)
    }

    @Test("a latent decodes to the reference's mel within float32 noise, cropped to 4L - 3 frames")
    func decodeMatches() throws {
        let fixture = try Fixture.load("audio_decoder")
        let decoder = try Self.loaded(fixture)
        let mel = decoder.decode(decoder.unpacked(try #require(fixture["in.tokens"])))
        let expected = try #require(fixture["out.mel"])
        #expect(mel.shape == [1, 2, 17, 8])
        #expect(mel.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(mel, expected) < 1e-3)
    }

    @Test("the real layout's arithmetic: 51 latent frames are 201 mel frames of 64 bins, 128 wide packed")
    func realLayout() {
        let layout = LTX2AudioDecoderLayout.ltx25
        #expect(layout.melFrames(forLatentFrames: 51) == 201)
        #expect(layout.melBins == 64)
        #expect(layout.packedChannels == 128)
    }
}
