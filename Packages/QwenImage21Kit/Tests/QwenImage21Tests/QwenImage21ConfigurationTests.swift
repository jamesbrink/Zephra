import Foundation
import Testing
import ZephraTestSupport

@testable import QwenImage21

@Suite("Every config is decoded up front, and the ones that would be silently wrong are refused")
struct QwenImage21ConfigurationTests {
    @Test("a minimal snapshot decodes every file and both cross-file invariants hold")
    func minimalSnapshotDecodes() throws {
        let scratch = Scratch("QwenImage21Configuration")
        defer { withExtendedLifetime(scratch) {} }
        let snapshot = try MinimalSnapshot.write(into: scratch)
        let configuration = try QwenImage21Configuration(readingFrom: snapshot)

        #expect(configuration.transformer.patchSize == 1)
        #expect(configuration.transformer.causalCondition)
        #expect(configuration.transformer.innerDim == 32)
        #expect(configuration.transformer.mlpHiddenSize == 96)
        #expect(configuration.transformer.outChannels == 8)
        #expect(configuration.vae.inChannels == 4, "RGBA, in and out")
        #expect(configuration.vae.outChannels == 4)
        #expect(configuration.vae.latentsMean.count == configuration.vae.zDim)
        #expect(configuration.textEncoder.text.numKeyValueHeads == 1)
        #expect(configuration.textEncoder.text.ropeScaling.mropeInterleaved)
        #expect(configuration.textEncoder.vision.headDim == 16)
        #expect(configuration.textEncoder.imageTokenID == 151_655)
        #expect(configuration.scheduler.shiftTerminal == 0.02)
        #expect(configuration.processor.tokensPerSlot == 4)
        #expect(configuration.sizeAlignment == 32)
    }

    @Test("a missing file names the file rather than failing somewhere later")
    func missingFileIsNamed() throws {
        let scratch = Scratch("QwenImage21Configuration")
        defer { withExtendedLifetime(scratch) {} }
        let snapshot = try MinimalSnapshot.write(into: scratch)
        try FileManager.default.removeItem(at: snapshot.appending(path: "vae/config.json"))
        #expect(throws: QwenImage21ConfigurationError.self) {
            _ = try QwenImage21Configuration(readingFrom: snapshot)
        }
    }

    @Test("a patch size other than one is refused: this port owes no patchify")
    func patchifyIsRefused() throws {
        let scratch = Scratch("QwenImage21Configuration")
        defer { withExtendedLifetime(scratch) {} }
        let transformer = MinimalSnapshot.transformerJSON
            .replacingOccurrences(of: "\"patch_size\": 1", with: "\"patch_size\": 2")
        let snapshot = try MinimalSnapshot.write(into: scratch, transformer: transformer)
        #expect(throws: QwenImage21ConfigurationError.self) {
            _ = try QwenImage21Configuration(readingFrom: snapshot)
        }
    }

    @Test("rotary axes that do not fill a head are refused")
    func ropeAxesMustFillTheHead() throws {
        let scratch = Scratch("QwenImage21Configuration")
        defer { withExtendedLifetime(scratch) {} }
        let transformer = MinimalSnapshot.transformerJSON
            .replacingOccurrences(of: "[4, 6, 6]", with: "[4, 6, 4]")
        let snapshot = try MinimalSnapshot.write(into: scratch, transformer: transformer)
        #expect(throws: QwenImage21ConfigurationError.self) {
            _ = try QwenImage21Configuration(readingFrom: snapshot)
        }
    }

    @Test("three picture channels are refused, because alpha would go quietly")
    func threeChannelsAreRefused() throws {
        let scratch = Scratch("QwenImage21Configuration")
        defer { withExtendedLifetime(scratch) {} }
        let vae = MinimalSnapshot.vaeJSON
            .replacingOccurrences(of: "\"in_channels\": 4", with: "\"in_channels\": 3")
        let snapshot = try MinimalSnapshot.write(into: scratch, vae: vae)
        #expect(throws: QwenImage21ConfigurationError.self) {
            _ = try QwenImage21Configuration(readingFrom: snapshot)
        }
    }

    @Test("a latent whose channels are not the transformer's input is refused")
    func channelsMustMatch() throws {
        let scratch = Scratch("QwenImage21Configuration")
        defer { withExtendedLifetime(scratch) {} }
        let vae = MinimalSnapshot.vaeJSON.replacingOccurrences(
            of: "\"z_dim\": 8", with: "\"z_dim\": 16")
        let snapshot = try MinimalSnapshot.write(into: scratch, vae: vae)
        #expect(throws: QwenImage21ConfigurationError.self) {
            _ = try QwenImage21Configuration(readingFrom: snapshot)
        }
    }

    @Test("a sectioned multimodal rotary is refused; 2.1's is interleaved")
    func sectionedRopeIsRefused() throws {
        let scratch = Scratch("QwenImage21Configuration")
        defer { withExtendedLifetime(scratch) {} }
        let encoder = MinimalSnapshot.textEncoderJSON
            .replacingOccurrences(of: "\"mrope_interleaved\": true", with: "\"mrope_interleaved\": false")
        let snapshot = try MinimalSnapshot.write(into: scratch, textEncoder: encoder)
        #expect(throws: QwenImage21ConfigurationError.self) {
            _ = try QwenImage21Configuration(readingFrom: snapshot)
        }
    }

    @Test("model_index.json is read when it is there and absent is not an error")
    func modelIndexIsOptional() throws {
        let scratch = Scratch("QwenImage21Configuration")
        defer { withExtendedLifetime(scratch) {} }
        let snapshot = try MinimalSnapshot.write(into: scratch)
        let index = try #require(try QwenImage21Configuration.modelIndex(in: snapshot))
        #expect(index.className == "QwenImage21Pipeline")
        #expect(index.components["transformer"]?.className == "QwenImage21Transformer2DModel")
        #expect(index.components["vae"]?.library == "diffusers")

        let bare = Scratch("QwenImage21Configuration")
        defer { withExtendedLifetime(bare) {} }
        let without = try MinimalSnapshot.write(into: bare, modelIndex: nil)
        let absent = try QwenImage21Configuration.modelIndex(in: without)
        #expect(absent == nil)
    }

    @Test("a model_index naming Qwen-Image rather than Qwen-Image 2.1 is refused")
    func modelIndexNamesThePipeline() throws {
        let scratch = Scratch("QwenImage21Configuration")
        defer { withExtendedLifetime(scratch) {} }
        let index = MinimalSnapshot.modelIndexJSON
            .replacingOccurrences(of: "QwenImage21Transformer2DModel", with: "QwenImageTransformer2DModel")
        let snapshot = try MinimalSnapshot.write(into: scratch, modelIndex: index)
        #expect(throws: QwenImage21ConfigurationError.self) {
            _ = try QwenImage21Configuration.modelIndex(in: snapshot)
        }
    }
}
