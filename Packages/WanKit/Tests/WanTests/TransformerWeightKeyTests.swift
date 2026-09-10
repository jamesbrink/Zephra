import Foundation
import MLX
import MLXNN
import Testing
import ZephraQuantization
import ZephraTestSupport

@testable import Wan

/// Every tensor the release ships, accounted for before a weight is read.
///
/// The module tree is built at the real size — lazily, MLX allocates nothing until an array
/// is evaluated — and its parameter paths are mapped back to the checkpoint's names, so a
/// rename, a miscounted block or a tensor this port forgot shows up here as a name on one
/// side and not the other. Headers only: the 10 GB shard is checked in a second.
@Suite("Every published transformer tensor is accounted for")
struct TransformerWeightKeyTests {
    @Test("the three list indices fold into the module tree and back")
    func renames() {
        let pairs = [
            ("blocks.3.attn1.to_out.0.weight", "blocks.3.attn1.to_out.weight"),
            ("blocks.3.attn2.to_out.0.bias", "blocks.3.attn2.to_out.bias"),
            ("blocks.29.ffn.net.0.proj.weight", "blocks.29.ffn.proj_in.weight"),
            ("blocks.29.ffn.net.2.bias", "blocks.29.ffn.proj_out.bias"),
            ("blocks.0.attn1.norm_q.weight", "blocks.0.attn1.norm_q.weight"),
            ("condition_embedder.time_embedder.linear_1.weight", "condition_embedder.time_embedder.linear_1.weight"),
            ("scale_shift_table", "scale_shift_table"),
        ]
        for (checkpoint, module) in pairs {
            #expect(WanTransformerWeights.moduleName(of: checkpoint) == module)
            #expect(WanTransformerWeights.checkpointName(of: module) == checkpoint)
        }
    }

    @Test("the doll's-house fixture's names all land on a parameter, and every parameter is filled")
    func fixtureCoverage() throws {
        let fixture = try Fixture.load("transformer_model")
        let published = Set(Fixture.weights(fixture, under: "model.").keys)
        let claimed = Set(
            WanTransformer(TransformerParityTests.configuration).parameters().flattened()
                .map { WanTransformerWeights.checkpointName(of: $0.0) })
        Self.expectNamesMatch(published: published, claimed: claimed)
    }

    @Test(
        "the real release's transformer shard is claimed tensor for tensor",
        .enabled(if: SnapshotUnderTest.wan.hasRelease))
    func release() throws {
        let release = try #require(SnapshotUnderTest.wan.release)
        let directory = release.appending(path: "transformer")
        let configuration = try WanTransformerConfiguration(readingFrom: directory.appending(path: "config.json"))
        #expect(configuration == WanTransformerConfiguration())
        let header = try SafeTensorsHeader(contentsOf: directory.appending(path: "diffusion_pytorch_model.safetensors"))
        let published = Set(header.entries.map(\.name))
        let claimed = Set(
            WanTransformer(configuration).parameters().flattened()
                .map { WanTransformerWeights.checkpointName(of: $0.0) })
        #expect(published.count == 825)
        Self.expectNamesMatch(published: published, claimed: claimed)
        // The patch kernel is stored in PyTorch's order and turned round at load.
        let kernel = try #require(header.entries.first { $0.name == "patch_embedding.weight" })
        #expect(kernel.shape == [3072, 48, 1, 2, 2])
        #expect(WanTransformer(configuration).patchEmbedding.weight.shape == [3072, 1, 2, 2, 48])
    }

    private static func expectNamesMatch(published: Set<String>, claimed: Set<String>) {
        let absent = claimed.subtracting(published)
        let unclaimed = published.subtracting(claimed)
        #expect(absent.isEmpty, Comment(rawValue: "expected but absent: \(absent.sorted().prefix(8))"))
        #expect(unclaimed.isEmpty, Comment(rawValue: "present but unclaimed: \(unclaimed.sorted().prefix(8))"))
    }
}
