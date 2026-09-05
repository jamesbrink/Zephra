import Foundation
import Testing
import ZephraCore
import ZephraTestSupport

@testable import QwenImage

/// The published configuration, pinned. These numbers decide every tensor shape in the package,
/// so a silent change upstream should fail here rather than three milestones later.
@Suite("Qwen-Image configuration")
struct QwenImageConfigurationTests {
    @Test(
        "the published snapshot decodes to the shapes this package is built for",
        .enabled(if: SnapshotUnderTest.qwenImage.isPresent))
    func decodesThePublishedSnapshot() throws {
        let snapshot = try #require(SnapshotUnderTest.qwenImage.directory)
        let configuration = try QwenImageConfiguration(readingFrom: snapshot)

        let transformer = configuration.transformer
        #expect(transformer.numLayers == 60)
        #expect(transformer.numAttentionHeads == 24)
        #expect(transformer.attentionHeadDim == 128)
        #expect(transformer.innerDim == 3072)
        #expect(transformer.modulationDim == 18432)
        #expect(transformer.axesDimsRope == [16, 56, 56])
        #expect(transformer.inChannels == 64)
        #expect(transformer.outChannels == 16)
        #expect(transformer.patchSize == 2)
        #expect(transformer.jointAttentionDim == 3584)
        #expect(!transformer.guidanceEmbeds, "2512 takes no distilled guidance input")

        let vae = configuration.vae
        #expect(vae.zDim == 16)
        #expect(vae.baseDim == 96)
        #expect(vae.dimMult == [1, 2, 4, 4])
        #expect(vae.spatialScale == 8)
        #expect(vae.numResBlocks == 2)
        #expect(vae.attnScales.isEmpty, "the only attention is the middle block's")
        #expect(vae.temperalDownsample == [false, true, true])
        #expect(vae.latentsMean.count == 16)

        let encoder = configuration.textEncoder
        #expect(encoder.hiddenSize == 3584)
        #expect(encoder.numHiddenLayers == 28)
        #expect(encoder.numAttentionHeads == 28)
        #expect(encoder.numKeyValueHeads == 4)
        #expect(encoder.headDim == 128)
        #expect(encoder.queryHeadsPerKeyValueHead == 7)
        #expect(encoder.intermediateSize == 18944)
        #expect(encoder.vocabSize == 152_064)

        let scheduler = configuration.scheduler
        #expect(scheduler.useDynamicShifting)
        #expect(scheduler.baseShift == 0.5)
        #expect(scheduler.maxShift == 0.9)
        #expect(scheduler.timeShiftType == "exponential")
        #expect(
            scheduler.shiftTerminal == 0.02,
            "older flow-matching schedulers have no terminal shift, so it is easily dropped")
    }

    @Test("the catalog's alignment is the snapshot's own",
          .enabled(if: SnapshotUnderTest.qwenImage.isPresent))
    func catalogAlignmentIsTheSnapshots() throws {
        let snapshot = try #require(SnapshotUnderTest.qwenImage.directory)
        let configuration = try QwenImageConfiguration(readingFrom: snapshot)
        #expect(ModelCatalog.qwenImage2512_4bit.capabilities.sizeAlignment == configuration.sizeAlignment)
    }

    @Test("a config asking for a guidance embedder is refused rather than ignored")
    func guidanceEmbedderIsRefused() throws {
        let json = #"""
            {"attention_head_dim": 128, "axes_dims_rope": [16, 56, 56],
             "guidance_embeds": true, "in_channels": 64, "joint_attention_dim": 3584,
             "num_attention_heads": 24, "num_layers": 60, "out_channels": 16, "patch_size": 2}
            """#
        let configuration = try JSONDecoder().decode(
            QwenImageTransformerConfiguration.self, from: Data(json.utf8))
        #expect(throws: QwenImageConfigurationError.unsupportedValue(field: "guidance_embeds", value: "true")) {
            try configuration.validated()
        }
    }

    @Test("a shift the scheduler does not implement, and an attention scale, are refused")
    func unsupportedSchedulerAndVAEValuesAreRefused() throws {
        let linear = QwenImageSchedulerConfiguration(
            numTrainTimesteps: 1000, shift: 1, useDynamicShifting: true, baseShift: 0.5,
            maxShift: 0.9, baseImageSeqLen: 256, maxImageSeqLen: 8192, shiftTerminal: 0.02,
            timeShiftType: "linear")
        #expect(throws: QwenImageConfigurationError.unsupportedValue(field: "time_shift_type", value: "linear")) {
            try linear.validated()
        }
        let vae = QwenImageVAEConfiguration(
            baseDim: 8, zDim: 4, dimMult: [1, 2], numResBlocks: 1, attnScales: [1.0],
            temperalDownsample: [true], latentsMean: [0, 0, 0, 0], latentsStd: [1, 1, 1, 1])
        #expect(throws: QwenImageConfigurationError.unsupportedValue(field: "attn_scales", value: "[1.0]")) {
            try vae.validated()
        }
    }

    @Test("rotary axes that do not partition the head width are rejected")
    func rejectsInconsistentRopeAxes() throws {
        let broken = #"""
            {"attention_head_dim": 128, "axes_dims_rope": [16, 56, 32],
             "guidance_embeds": false, "in_channels": 64, "joint_attention_dim": 3584,
             "num_attention_heads": 24, "num_layers": 60, "out_channels": 16, "patch_size": 2}
            """#
        let configuration = try JSONDecoder().decode(
            QwenImageTransformerConfiguration.self, from: Data(broken.utf8))
        #expect(throws: QwenImageConfigurationError.self) { try configuration.validated() }
    }
}
