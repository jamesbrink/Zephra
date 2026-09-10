import Foundation
import MLX
import MLXNN
import Testing
import ZephraQuantization
import ZephraTestSupport

@testable import LTX2

/// The published upsampler's tensors, accounted for before a weight is read.
///
/// The tree is built at the real size -- lazily, MLX allocates nothing until an array is
/// evaluated -- and its parameter paths are mapped to the pack's names, so a rename, a
/// miscounted block, a kernel in the wrong layout or a tensor this port forgot shows up as a
/// name or a shape on one side and not the other. Headers only: the gigabyte file is checked in
/// a moment. The file is the second stage's alone, so the suite gates on it rather than on the
/// release.
@Suite("the real upsampler's tensors are exactly the tree's parameters")
struct UpsamplerWeightKeyTests {
    @Test(
        "every published name and shape is a parameter of the x2 tree, and every parameter is published",
        .enabled(if: SnapshotUnderTest.ltx2.hasUpsamplerFile))
    func keysAndShapes() throws {
        let release = try #require(SnapshotUnderTest.ltx2.release)
        let header = try SafeTensorsHeader(
            contentsOf: release.appending(path: "spatial_upscaler_x2_v1_1.safetensors"))
        let published = header.entries.reduce(into: [String: [Int]]()) { $0[$1.name] = $1.shape }
        let tree = LTX2LatentUpsampler(.x2).parameters().flattened().reduce(into: [String: [Int]]()) {
            $0[LTX2UpsamplerWeights.checkpointName(of: $1.0)] = $1.1.shape
        }
        #expect(published.count == 72)
        #expect(tree.count == 72)
        let absent = Set(tree.keys).subtracting(published.keys)
        let unclaimed = Set(published.keys).subtracting(tree.keys)
        #expect(absent.isEmpty, Comment(rawValue: "expected but absent: \(absent.sorted().prefix(8))"))
        #expect(unclaimed.isEmpty, Comment(rawValue: "present but unclaimed: \(unclaimed.sorted().prefix(8))"))
        for (name, shape) in published {
            #expect(tree[name] == shape, "\(name)")
        }
        // The kernels are channels-last in the file, as the tree holds them: no transpose at load.
        #expect(published["spatial_upscaler_x2_v1_1.initial_conv.weight"] == [1024, 3, 3, 3, 128])
        #expect(published["spatial_upscaler_x2_v1_1.upsampler.0.weight"] == [4096, 3, 3, 1024])
    }

    @Test(
        "the config beside the file reads to the published configuration",
        .enabled(if: SnapshotUnderTest.ltx2.hasUpsamplerFile))
    func configuration() throws {
        let release = try #require(SnapshotUnderTest.ltx2.release)
        let configuration = try LTX2UpsamplerConfiguration(
            readingFrom: release.appending(path: "spatial_upscaler_x2_v1_1_config.json"))
        #expect(configuration == .x2)
    }

    @Test("the prefix is stripped and anything under another prefix dropped")
    func sanitized() {
        let renamed = LTX2UpsamplerWeights.sanitized([
            "spatial_upscaler_x2_v1_1.final_conv.bias": MLXArray.zeros([128]),
            "vae_decoder.per_channel_statistics.std": MLXArray.zeros([128]),
        ])
        #expect(Array(renamed.keys) == ["final_conv.bias"])
        #expect(LTX2UpsamplerWeights.checkpointName(of: "upsampler.0.weight") == "spatial_upscaler_x2_v1_1.upsampler.0.weight")
    }
}
