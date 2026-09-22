import Foundation
import Testing
import ZephraTestSupport

@testable import QwenImage21

@Suite("The published release decodes to the numbers this port is written against")
struct PublishedConfigurationTests {
    private static var snapshot: URL? { SnapshotUnderTest.qwenImage21.release }

    @Test(
        "every config in the release reads, and the transformer is 2.1's shape",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func transformerIsTheShippedShape() throws {
        let configuration = try QwenImage21Configuration(readingFrom: #require(Self.snapshot))
        let transformer = configuration.transformer
        #expect(transformer.attentionHeadDim == 128)
        #expect(transformer.axesDimsRope == [16, 56, 56])
        #expect(transformer.contextInDim == 4096)
        #expect(transformer.inChannels == 64)
        #expect(transformer.outChannels == 64)
        #expect(transformer.numAttentionHeads == 32)
        #expect(transformer.numLayers == 32)
        #expect(transformer.patchSize == 1, "no patchify anywhere in 2.1")
        #expect(transformer.causalCondition)
        #expect(transformer.innerDim == 4096)
        #expect(transformer.mlpHiddenSize == 12288)
    }

    @Test(
        "the autoencoder carries alpha and 64 latent channels at 16 pixels a cell",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func vaeIsTheShippedShape() throws {
        let vae = try QwenImage21Configuration(readingFrom: #require(Self.snapshot)).vae
        #expect(vae.inChannels == 4)
        #expect(vae.outChannels == 4)
        #expect(vae.zDim == 64)
        #expect(vae.baseDim == 96)
        #expect(vae.decoderBaseDim == 144)
        #expect(vae.dimMult == [1, 2, 4, 8, 8])
        #expect(vae.numResBlocks == 2)
        #expect(vae.isResidual)
        #expect(vae.scaleFactorSpatial == 16)
        #expect(vae.latentsMean.count == 64)
        #expect(vae.latentsStd.count == 64)
        #expect(abs(vae.latentsMean[0] - 0.5126) < 1e-9)
        #expect(abs(vae.latentsStd[0] - 3.2001) < 1e-9)
        #expect(vae.latentsStd.allSatisfy { $0 > 0 }, "a zero would divide the latent away")
    }

    @Test(
        "the text encoder is Qwen3-VL: 36 decoder layers, a 27-block tower, three DeepStack taps",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func textEncoderIsTheShippedShape() throws {
        let encoder = try QwenImage21Configuration(readingFrom: #require(Self.snapshot)).textEncoder
        #expect(encoder.text.numHiddenLayers == 36)
        #expect(encoder.text.hiddenSize == 4096)
        #expect(encoder.text.numAttentionHeads == 32)
        #expect(encoder.text.numKeyValueHeads == 8)
        #expect(encoder.text.headDim == 128)
        #expect(encoder.text.intermediateSize == 12288)
        #expect(encoder.text.ropeTheta == 5_000_000)
        #expect(encoder.text.ropeScaling.mropeSection == [24, 20, 20])
        #expect(encoder.text.ropeScaling.mropeInterleaved)
        #expect(encoder.text.vocabSize == 151_936)
        #expect(encoder.vision.depth == 27)
        #expect(encoder.vision.hiddenSize == 1152)
        #expect(encoder.vision.numHeads == 16)
        #expect(encoder.vision.headDim == 72)
        #expect(encoder.vision.intermediateSize == 4304)
        #expect(encoder.vision.patchSize == 16)
        #expect(encoder.vision.temporalPatchSize == 2)
        #expect(encoder.vision.spatialMergeSize == 2)
        #expect(encoder.vision.numPositionEmbeddings == 2304)
        #expect(encoder.vision.outHiddenSize == 4096)
        #expect(encoder.vision.deepstackVisualIndexes == [8, 16, 24])
        #expect(encoder.imageTokenID == 151_655)
        #expect(encoder.visionStartTokenID == 151_652)
        #expect(encoder.visionEndTokenID == 151_653)
    }

    @Test(
        "the scheduler ships the constants the shift and the stretch are computed from",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func schedulerIsTheShippedShape() throws {
        let scheduler = try QwenImage21Configuration(readingFrom: #require(Self.snapshot)).scheduler
        #expect(scheduler.baseImageSeqLen == 256)
        #expect(scheduler.baseShift == 0.5)
        #expect(scheduler.maxImageSeqLen == 8192)
        #expect(scheduler.maxShift == 0.9)
        #expect(scheduler.numTrainTimesteps == 1000)
        #expect(scheduler.shiftTerminal == 0.02)
        #expect(scheduler.useDynamicShifting)
        #expect(scheduler.timeShiftType == "exponential")
        // The defaults the port stands on when there is no snapshot must be these.
        #expect(scheduler == QwenImage21SchedulerConfiguration(shift: scheduler.shift))
    }

    @Test(
        "the processor's patch and merge decide how many slots a picture costs",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func processorIsTheShippedShape() throws {
        let configuration = try QwenImage21Configuration(readingFrom: #require(Self.snapshot))
        #expect(configuration.processor.patchSize == 16)
        #expect(configuration.processor.mergeSize == 2)
        #expect(configuration.processor.temporalPatchSize == 2)
        #expect(configuration.processor.tokensPerSlot == 4)
        #expect(configuration.processor.imageMean == [0.5, 0.5, 0.5])
        #expect(configuration.processor.resample == 3, "bicubic")
        #expect(configuration.sizeAlignment == 32)
    }
}
