import Foundation
import MLX
import Testing
import ZephraMLX

@testable import LTX2

@Suite("the adaLN-single head reproduces the reference's modulation rows")
struct TimestepEmbeddingTests {
    @Test("nine rows and the embedded timestep match for three noise levels")
    func modulation() throws {
        let fixture = try Fixture.load("timestep")
        let head = LTX2AdaLayerNormSingle(dim: 32, rows: 9, timestepScale: 1000)
        try PackedWeightLoading.load(
            into: head,
            weights: LTX2TransformerWeights.sanitized(Fixture.weights(fixture, under: "model.")),
            manifest: nil)

        let (modulation, embedded) = head(try #require(fixture["in.sigma"]), dtype: .float32)
        #expect(modulation.shape == [3, 1, 9, 32])
        #expect(embedded.shape == [3, 1, 32])
        let expectedModulation = try #require(fixture["out.modulation"]).reshaped([3, 1, 9, 32])
        let expectedEmbedded = try #require(fixture["out.embedded"]).reshaped([3, 1, 32])
        #expect(Fixture.maxAbsoluteDifference(modulation, expectedModulation) < 2e-4)
        #expect(Fixture.maxAbsoluteDifference(embedded, expectedEmbedded) < 2e-4)
    }

    @Test("the sinusoid is cosines first and scaled by a thousand")
    func sinusoid() {
        let embedding = LTX2TimestepEmbedding(embeddingDim: 8, timestepScale: 1000)
        let projected = embedding.sinusoid(MLXArray([0.5] as [Float])).asArray(Float.self)
        #expect(projected.count == 256)
        // The first frequency is 1, so the leading cosine is cos(500) and channel 128 is sin(500).
        #expect(abs(projected[0] - Foundation.cos(Float(500))) < 1e-4)
        #expect(abs(projected[128] - Foundation.sin(Float(500))) < 1e-4)
    }

    @Test("the pack's nested embedder name folds into the module tree and back")
    func names() {
        let packed = "transformer.adaln_single.emb.timestep_embedder.linear1.weight"
        #expect(LTX2TransformerWeights.moduleName(of: packed) == "adaln_single.emb.linear1.weight")
        #expect(LTX2TransformerWeights.checkpointName(of: "adaln_single.emb.linear1.weight") == packed)
        #expect(LTX2TransformerWeights.moduleName(of: "transformer.transformer_blocks.3.ff.proj_in.weight")
            == "transformer_blocks.3.ff.proj_in.weight")
        #expect(LTX2TransformerWeights.isAudio("transformer.transformer_blocks.0.audio_to_video_attn.to_q.weight"))
        #expect(LTX2TransformerWeights.isAudio("transformer.av_ca_a2v_gate_adaln_single.linear.weight"))
        #expect(!LTX2TransformerWeights.isAudio("transformer.transformer_blocks.0.attn2.to_q.weight"))
    }
}
