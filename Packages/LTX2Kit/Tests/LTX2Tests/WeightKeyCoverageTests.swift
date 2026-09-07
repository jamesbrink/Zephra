import Foundation
import MLX
import MLXNN
import Testing
import ZephraQuantization
import ZephraTestSupport

@testable import LTX2

/// Every tensor the pack ships, accounted for before a weight is read.
///
/// The module trees are built at the real size — lazily, MLX allocates nothing until an array
/// is evaluated — and their parameter paths are mapped back to the pack's names, so a rename,
/// a miscounted block or a tensor this port forgot shows up here as a name on one side and not
/// the other. Headers only: the 69 GB pack is checked in a second.
@Suite("Every published tensor is accounted for")
struct WeightKeyCoverageTests {
    @Test(
        "the transformer's video lane claims every non-audio tensor, and only those",
        .enabled(if: SnapshotUnderTest.ltx2.hasRelease))
    func transformer() throws {
        let release = try #require(SnapshotUnderTest.ltx2.release)
        let published = try Self.keys(release.appending(path: "transformer-distilled.safetensors"))
        let video = published.filter { !LTX2TransformerWeights.isAudio($0) }
        let claimed = Set(
            LTX2Transformer(LTX2TransformerConfiguration()).parameters().flattened()
                .map { LTX2TransformerWeights.checkpointName(of: $0.0) })
        #expect(published.count == 4091)
        #expect(video.count == 1362)
        Self.expectNamesMatch(published: video, claimed: claimed)
    }

    @Test(
        "the connector and the projection claim every video-side tensor",
        .enabled(if: SnapshotUnderTest.ltx2.hasRelease))
    func connector() throws {
        let release = try #require(SnapshotUnderTest.ltx2.release)
        let published = try Self.keys(release.appending(path: "connector.safetensors"))
        let video = published.filter { !$0.contains("audio") }
        let connector = LTX2TextConnector(dim: 4096, heads: 32, layers: LTX2TextConnector.defaultLayers)
        let extractor = LTX2FeatureExtractor(hiddenSize: 3840, stateCount: 49, outputSize: 4096)
        let claimed = Set(
            connector.parameters().flattened().map { LTX2ConnectorWeights.checkpointName(of: $0.0) }
                + extractor.parameters().flattened().map { LTX2ConnectorWeights.projectionPrefix + $0.0 })
        #expect(published.count == 262)
        Self.expectNamesMatch(published: video, claimed: claimed)
    }

    @Test(
        "Gemma's tree claims every tensor in its file: nothing is skipped and nothing is wasted",
        .enabled(if: SnapshotUnderTest.ltx2.hasRelease))
    func textEncoder() throws {
        let release = try #require(SnapshotUnderTest.ltx2.release)
        let directory = release.appending(path: "gemma4-12b-ltx-v1")
        let published = try Self.keys(directory.appending(path: "model.safetensors"))
        let configuration = try Gemma4Configuration(readingFrom: directory.appending(path: "config.json"))
        let claimed = Set(
            Gemma4TextModel(configuration).parameters().flattened()
                .map { Gemma4TextModel.checkpointPrefix + $0.0 })
        #expect(published.count == 666)
        Self.expectNamesMatch(published: published, claimed: claimed)
    }

    /// The encoder is the one file this suite may not find: a Mac that fetched the pack before
    /// a first frame could be held has every other file and not this one, so the test is gated
    /// on the file rather than on the release.
    @Test(
        "the video encoder's tree claims every tensor in its file",
        .enabled(if: SnapshotUnderTest.ltx2.hasEncoderFile))
    func videoEncoder() throws {
        let release = try #require(SnapshotUnderTest.ltx2.release)
        let published = try Self.keys(release.appending(path: "vae_encoder.safetensors"))
        let claimed = Set(
            LTX2VideoEncoder(.ltx25).parameters().flattened()
                .map { LTX2VAEWeights.encoderCheckpointName(of: $0.0) })
        #expect(published.count == 86)
        Self.expectNamesMatch(published: published, claimed: claimed)
    }

    private static func keys(_ file: URL) throws -> Set<String> {
        Set(try SafeTensorsHeader(contentsOf: file).entries.map(\.name))
    }

    private static func expectNamesMatch(published: Set<String>, claimed: Set<String>) {
        let absent = claimed.subtracting(published)
        let unclaimed = published.subtracting(claimed)
        #expect(absent.isEmpty, Comment(rawValue: "expected but absent: \(absent.sorted().prefix(8))"))
        #expect(unclaimed.isEmpty, Comment(rawValue: "present but unclaimed: \(unclaimed.sorted().prefix(8))"))
    }
}
