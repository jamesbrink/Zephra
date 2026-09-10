import Foundation
import MLX
import MLXNN
import Testing
import ZephraQuantization
import ZephraTestSupport

@testable import Wan

/// Every tensor the release's text encoder ships, accounted for before a weight is read.
///
/// The module tree is built at the real size -- lazily, MLX allocates nothing until an array
/// is evaluated -- from the release's own `config.json`, and its parameter paths are compared
/// with the names in `model.safetensors.index.json` and in the three shards' headers, so a
/// rename, a miscounted block or a tensor this port forgot shows up as a name on one side and
/// not the other. Headers only: the 11 GB is checked in under a second.
@Suite("Every published text encoder tensor is accounted for", .enabled(if: SnapshotUnderTest.wan.hasRelease))
struct TextEncoderWeightKeyTests {
    static func claimed() throws -> Set<String> {
        let release = try #require(SnapshotUnderTest.wan.release)
        let configuration = try UMT5Configuration(
            readingFrom: release.appending(path: "text_encoder/config.json"))
        #expect(configuration.numLayers == 24 && configuration.dModel == 4096 && configuration.numHeads == 64)
        return Set(UMT5TextEncoder(configuration).parameters().flattened().map(\.0))
    }

    @Test("the tree claims every tensor the index names, and only those")
    func indexNamesMatch() throws {
        let release = try #require(SnapshotUnderTest.wan.release)
        let index = try JSONDecoder().decode(
            Index.self, from: Data(contentsOf: release.appending(path: "text_encoder/model.safetensors.index.json")))
        let published = Set(index.weightMap.keys)
        #expect(published.count == 242)
        #expect(published.contains("shared.weight"))
        #expect(!published.contains("encoder.embed_tokens.weight"))
        Self.expectNamesMatch(published: published, claimed: try Self.claimed())
    }

    @Test("the shards' headers carry exactly the same names")
    func shardHeadersMatch() throws {
        let release = try #require(SnapshotUnderTest.wan.release)
        let directory = release.appending(path: "text_encoder")
        let shards = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "safetensors" }
        #expect(shards.count == 3)
        var published: Set<String> = []
        for shard in shards {
            for entry in try SafeTensorsHeader(contentsOf: shard).entries {
                #expect(published.insert(entry.name).inserted, Comment(rawValue: "\(entry.name) is in two shards"))
            }
        }
        Self.expectNamesMatch(published: published, claimed: try Self.claimed())
    }

    private struct Index: Decodable {
        let weightMap: [String: String]
        enum CodingKeys: String, CodingKey { case weightMap = "weight_map" }
    }

    private static func expectNamesMatch(published: Set<String>, claimed: Set<String>) {
        let absent = claimed.subtracting(published)
        let unclaimed = published.subtracting(claimed)
        #expect(absent.isEmpty, Comment(rawValue: "expected but absent: \(absent.sorted().prefix(8))"))
        #expect(unclaimed.isEmpty, Comment(rawValue: "present but unclaimed: \(unclaimed.sorted().prefix(8))"))
    }
}
