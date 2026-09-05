import Foundation
import MLX
import Testing

@testable import Flux2

/// Serialized because the tiling test writes `Flux2Autoencoder.latentTile`, which is process-wide
/// by design -- a host sets it once for the model about to run.
@Suite(
    "The autoencoder reproduces the reference's encode and decode, batch-norm included",
    .serialized)
struct VAEParityTests {
    /// The doll's-house autoencoder `Tools/dump_vae.py` builds: two stages, four latent
    /// channels, four norm groups. Decoded from JSON rather than constructed, so the coding
    /// keys are exercised alongside everything else.
    static func configuration() throws -> Flux2VAEConfiguration {
        let json = """
            {
              "block_out_channels": [8, 16],
              "layers_per_block": 1,
              "latent_channels": 4,
              "norm_num_groups": 4,
              "mid_block_add_attention": true,
              "patch_size": [2, 2],
              "batch_norm_eps": 0.0001
            }
            """
        return try JSONDecoder()
            .decode(Flux2VAEConfiguration.self, from: Data(json.utf8))
            .validated()
    }

    /// The autoencoder with the fixture's weights in it.
    static func loaded(_ fixture: [String: MLXArray]) throws -> Flux2Autoencoder {
        let model = Flux2Autoencoder(try configuration())
        try model.load(weights: Fixture.weights(fixture, under: "vae."))
        return model
    }

    static func meanAbsoluteDifference(_ a: MLXArray, _ b: MLXArray) -> Float {
        MLX.mean(MLX.abs(a.asType(.float32) - b.asType(.float32))).item(Float.self)
    }

    /// Repeatable noise from a linear congruential generator, so the tiling test does not need
    /// a fixture of its own and does not depend on MLX's random stream.
    static func noise(_ shape: [Int]) -> MLXArray {
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        let values = (0..<shape.reduce(1, *)).map { _ -> Float in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Int32(truncatingIfNeeded: state >> 32)) / Float(Int32.max)
        }
        return MLXArray(values, shape)
    }

    @Test("a packed latent decodes to the reference's pixels")
    func decodeMatchesTheReference() throws {
        let fixture = try Fixture.load("vae")
        let model = try Self.loaded(fixture)

        let pixels = model.decodePacked(try #require(fixture["vae.in.packed"]))
        // The reference is dumped straight out of the decoder and this doll's house overshoots
        // -1 slightly, so the comparison clips it the way `decodePacked` clips its own output
        // and the way diffusers' image processor clips the real one.
        let reference = MLX.clip(
            try #require(fixture["vae.out.pixels"]).transposed(0, 2, 3, 1),
            min: MLXArray(Float(-1)), max: MLXArray(Float(1)))

        #expect(pixels.shape == reference.shape)
        let difference = Fixture.maxAbsoluteDifference(pixels, reference)
        #expect(difference < 1e-4, Comment(rawValue: "decode differs by \(difference)"))
    }

    @Test("an image encodes to the reference's packed, normalised latent")
    func encodeMatchesTheReference() throws {
        let fixture = try Fixture.load("vae")
        let model = try Self.loaded(fixture)

        let packed = model.encodePacked(try #require(fixture["vae.in.image"]))
        let reference = try #require(fixture["vae.out.packed"])

        #expect(packed.shape == reference.shape)
        let difference = Fixture.maxAbsoluteDifference(packed, reference)
        #expect(difference < 1e-4, Comment(rawValue: "encode differs by \(difference)"))
    }

    @Test("every published weight lands, and every parameter is filled")
    func weightNamesLineUp() throws {
        let fixture = try Fixture.load("vae")
        let published = Flux2VAEWeights.sanitized(Fixture.weights(fixture, under: "vae."))
        let model = Flux2Autoencoder(try Self.configuration())
        let wanted = Set(model.parameters().flattened().map(\.0))
        let provided = Set(published.keys)

        let unplaced = provided.subtracting(wanted).sorted()
        #expect(
            unplaced.isEmpty,
            Comment(rawValue: "the tree has no place for \(unplaced.joined(separator: ", "))"))
        let unfilled = wanted.subtracting(provided).sorted()
        #expect(
            unfilled.isEmpty,
            Comment(rawValue: "nothing fills \(unfilled.joined(separator: ", "))"))
    }

    @Test("tiling reassembles the same image, and its seams fade as the tile grows")
    func tilingReassemblesTheSameImage() throws {
        let fixture = try Fixture.load("vae")
        let model = try Self.loaded(fixture)
        // A 32-cell packed latent unpacks to 64 cells, which is four tiles across at the
        // smallest tile below and large enough for the blending to have work to do.
        let packed = Self.noise([1, 16, 32, 32])
        let whole = model.decodePacked(packed)

        // The tile is measured on the unpacked latent, so a 16-cell tile is 128 pixels here and
        // would be 128 pixels in the real model too. Getting that scale wrong -- reading it off
        // the published model's eight rather than off this configuration's two -- reassembles
        // the tiles into an image of the wrong size, which is what this pins.
        let quarters = model.decodePacked(packed, tile: 16)
        #expect(quarters.shape == whole.shape)

        let wide = model.decodePacked(packed, tile: 48)
        #expect(wide.shape == whole.shape)

        // A tile at least as wide as the latent is not a tiling at all, and takes the exact path.
        #expect(Fixture.maxAbsoluteDifference(model.decodePacked(packed, tile: 64), whole) == 0)

        // Tiling is an approximation because the group norms take their statistics over
        // whatever they are given, so a tile normalises against a tile. That error shrinks as
        // the tile approaches the image, and the four-of-255 figure the real model is tiled at
        // is only reachable here at the widest tile: these weights are random, so their
        // activations are not stationary across the image the way a trained decoder's are.
        let narrowError = Self.meanAbsoluteDifference(quarters, whole)
        let wideError = Self.meanAbsoluteDifference(wide, whole)
        #expect(
            wideError < narrowError,
            Comment(rawValue: "seams did not fade: \(narrowError) then \(wideError)"))
        #expect(
            wideError < 4.0 / 255.0,
            Comment(rawValue: "tiling moved the pixels by \(wideError)"))
    }
}
