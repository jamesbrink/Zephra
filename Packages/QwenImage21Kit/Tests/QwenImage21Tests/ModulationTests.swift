import Foundation
import MLX
import Testing

@testable import QwenImage21

@Suite("The timestep embedding and the one shared modulation table match the reference")
struct ModulationTests {
    @Test("the sinusoid puts cosines in the first half and sines in the second")
    func sinusoid() throws {
        let fixture = try Fixture.load("modulation")
        let projected = QwenImage21TimestepEmbedding.sinusoid(
            try #require(fixture["in.timestep"]))
        let expected = try #require(fixture["out.projected"])
        #expect(projected.shape == expected.shape)
        // Everything else in this kit agrees with the reference to about 1e-6. This lands at
        // 2.9e-5 and the whole of it is the frequency ladder: a handful of its 128 entries are
        // one float32 unit in the last place from `torch.exp`'s, the timestep multiplies them by
        // up to 1000, and the cosine of an angle 1e-4 radians out is 1e-4 out. See
        // `QwenImage21TimestepEmbedding.ladder`, which already builds the exponent in float32 to
        // get this far. A change that pushes it past this margin is far more likely to be a bug
        // than more of this.
        #expect(Fixture.maxAbsoluteDifference(projected, expected) < 1e-4)

        // The half that would look right either way: diffusers' ordinary `Timesteps` puts sine
        // first, so a helper lifted from another family's port produces a smooth, plausible and
        // wrong embedding. At t = 0 every angle is zero, so the first half is all ones and the
        // second all zeros, which says outright which way round this one is.
        let zeroed = QwenImage21TimestepEmbedding.sinusoid(MLXArray([Float(0)]))
        let channels = QwenImage21TimestepEmbedding.projectionChannels
        #expect(zeroed[0, 0].item(Float.self) == 1)
        #expect(zeroed[0, channels / 2].item(Float.self) == 0)
    }

    @Test("the conditioning and the table are the reference's")
    func table() throws {
        let fixture = try Fixture.load("transformer_model")
        let expected = try Fixture.load("modulation")
        let model = try TransformerFixture.model(fixture)

        let conditioning = model.timeEmbedding(
            try #require(expected["in.timestep"]), projectionDType: .float32)
        #expect(
            Fixture.maxAbsoluteDifference(conditioning, try #require(expected["out.temb"])) < 1e-4)
        #expect(
            Fixture.maxAbsoluteDifference(
                model.modulation(conditioning), try #require(expected["out.modulation"])) < 1e-4)
    }

    @Test("target tokens read their own timestep and everything before them reads t = 0")
    func rowSelection() throws {
        let fixture = try Fixture.load("modulation")
        let table = try #require(fixture["out.modulation"])
        let width = table.dim(-1) / 4
        let params = table[.ellipsis, ..<width]

        let mask = MLXArray(try Fixture.flags(fixture, "select.in.mask"))
        let masked = QwenImage21ModulationRows.select(params, targetTokenMask: mask)
        let expected = try #require(fixture["select.out.masked"])
        #expect(masked.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(masked, expected) < 1e-6)

        // No mask is the model without `causal_condition`: one row a sample, broadcast.
        let broadcast = QwenImage21ModulationRows.select(params, targetTokenMask: nil)
        let alone = try #require(fixture["select.out.broadcast"])
        #expect(broadcast.shape == alone.shape)
        #expect(Fixture.maxAbsoluteDifference(broadcast, alone) < 1e-6)
    }
}
