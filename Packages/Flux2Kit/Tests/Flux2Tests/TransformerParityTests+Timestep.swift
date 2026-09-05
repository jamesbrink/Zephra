import Foundation
import MLX
import MLXNN
import Testing

@testable import Flux2

/// The timestep under bfloat16, against a fixture dumped with the reference in bfloat16.
///
/// The float32 fixtures cannot see this: `timestep.to(hidden_states.dtype) * 1000` is the
/// identity in float32. Under bfloat16 it turns 0.77 into 768, and the top of the frequency
/// ladder is a radian per unit, so a port that keeps the sigma in float32 through the sinusoid
/// lands a different cosine in half the projection. `dump_timestep_bf16` in
/// `Tools/dump_transformer.py` records both the reference's answer and that other one.
extension TransformerParityTests {
    @Test("the conditioning under bfloat16 matches the reference's rounding of the timestep")
    func bfloat16TimestepRounding() throws {
        let fixture = try Fixture.load("timestep_bf16")
        let embedding = Flux2TimestepEmbedding(embeddingDim: 32)
        try embedding.update(
            parameters: ModuleParameters.unflattened(Fixture.weights(fixture, under: "temb.")),
            verify: .all)
        // As the transformer hands it over: the sigma cast to the stream's dtype first.
        let sigma = try #require(fixture["temb.in.sigma"]).asType(.bfloat16)

        // The projection is elementwise, so it is held to one bfloat16 unit in the last place
        // at the magnitude of a cosine.
        let projection = Flux2TimestepEmbedding.sinusoid(sigma).asType(.bfloat16)
        let expectedProjection = try #require(fixture["temb.out.projection"])
        #expect(expectedProjection.dtype == .bfloat16)
        let projectionDifference = Fixture.maxAbsoluteDifference(projection, expectedProjection)
        #expect(projectionDifference <= 1 / 128, "projection differs by \(projectionDifference)")

        // The MLP accumulates in whatever order the two backends choose, so the vector is held
        // to a few percent of its own scale — well inside what the rounding moves it by.
        let conditioning = embedding(sigma, projectionDType: .bfloat16)
        #expect(conditioning.dtype == .bfloat16)
        let expected = try #require(fixture["temb.out.conditioning"])
        let scale = MLX.max(MLX.abs(expected.asType(.float32))).item(Float.self)
        let difference = Fixture.maxAbsoluteDifference(conditioning, expected)
        #expect(difference < 0.05 * scale, "conditioning differs by \(difference) of \(scale)")

        // And the test has teeth: the reference's own float32 arithmetic, cast once at the
        // end — what this port did before — is nowhere near the bound.
        let unrounded = try #require(fixture["temb.out.unrounded"])
        let unroundedDifference = Fixture.maxAbsoluteDifference(unrounded, expected)
        #expect(unroundedDifference > 0.05 * scale, "the rounding is invisible at this sigma")
    }
}
