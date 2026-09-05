import Foundation
import Testing
import ZephraTestSupport

@testable import Flux2

@Suite("The published configuration decodes and says what the port assumes")
struct Flux2ConfigurationTests {
    @Test("every constant the port is built on is what the snapshot says",
          .enabled(if: SnapshotUnderTest.flux2Klein.isPresent))
    func publishedConstants() throws {
        let snapshot = try #require(SnapshotUnderTest.flux2Klein.directory)
        let configuration = try Flux2Configuration(readingFrom: snapshot)

        let transformer = configuration.transformer
        #expect(transformer.attentionHeadDim == 128)
        #expect(transformer.axesDimsRope == [32, 32, 32, 32])
        #expect(transformer.eps == 1e-6)
        #expect(!transformer.guidanceEmbeds, "klein is distilled: there is no guidance input")
        #expect(transformer.inChannels == 128)
        #expect(transformer.outChannels == 128, "out_channels is null, so it follows in_channels")
        #expect(transformer.jointAttentionDim == 7680)
        #expect(transformer.mlpRatio == 3.0)
        #expect(transformer.numAttentionHeads == 24)
        #expect(transformer.innerDim == 3072)
        #expect(transformer.mlpDim == 9216)
        #expect(transformer.fusedProjectionDim == 27648)
        #expect(transformer.numLayers == 5)
        #expect(transformer.numSingleLayers == 20)
        #expect(transformer.ropeTheta == 2000)
        #expect(transformer.timestepGuidanceChannels == 256)

        let encoder = configuration.textEncoder
        #expect(encoder.hiddenSize == 2560)
        #expect(encoder.numHiddenLayers == 36)
        #expect(encoder.numAttentionHeads == 32)
        #expect(encoder.numKeyValueHeads == 8)
        #expect(encoder.headDim == 128, "stated in the config; 2560 / 32 would be 80")
        #expect(encoder.intermediateSize == 9728)
        #expect(encoder.ropeTheta == 1_000_000)
        #expect(encoder.rmsNormEps == 1e-6)
        #expect(encoder.layersNeeded == 27)

        let vae = configuration.vae
        #expect(vae.blockOutChannels == [128, 256, 512, 512])
        #expect(vae.layersPerBlock == 2)
        #expect(vae.latentChannels == 32)
        #expect(vae.normNumGroups == 32)
        #expect(vae.midBlockAddAttention)
        #expect(vae.spatialScale == 8)
        #expect(vae.packedChannels == 128)
        #expect(vae.batchNormEps == 1e-4)

        let scheduler = configuration.scheduler
        #expect(scheduler.useDynamicShifting)
        #expect(scheduler.shiftTerminal == nil, "nothing stretches klein's tail")
        #expect(scheduler.timeShiftType == "exponential")
    }

    @Test("rotary axes that do not partition the head are refused")
    func ropeAxesMustSum() throws {
        let json = """
            {"attention_head_dim": 128, "axes_dims_rope": [32, 32, 32], "eps": 1e-6,
             "guidance_embeds": false, "in_channels": 128, "joint_attention_dim": 7680,
             "mlp_ratio": 3.0, "num_attention_heads": 24, "num_layers": 5,
             "num_single_layers": 20, "out_channels": null, "rope_theta": 2000,
             "timestep_guidance_channels": 256}
            """
        let decoded = try JSONDecoder().decode(
            Flux2TransformerConfiguration.self, from: Data(json.utf8))
        #expect(throws: Flux2ConfigurationError.ropeAxesDoNotSumToHeadDim(
            axes: [32, 32, 32], headDim: 128)) {
            try decoded.validated()
        }
    }

    @Test("an encoder shallower than the deepest tap is refused")
    func tapsMustBeReachable() throws {
        let json = """
            {"hidden_size": 64, "num_hidden_layers": 12, "num_attention_heads": 4,
             "num_key_value_heads": 2, "head_dim": 16, "intermediate_size": 128,
             "rms_norm_eps": 1e-6, "rope_theta": 1000000, "vocab_size": 100}
            """
        let decoded = try JSONDecoder().decode(
            Flux2TextEncoderConfiguration.self, from: Data(json.utf8))
        #expect(throws: Flux2ConfigurationError.hiddenStateTapBeyondStack(tap: 27, layers: 12)) {
            try decoded.validated()
        }
    }
}
