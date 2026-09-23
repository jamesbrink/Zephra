import Foundation
import Testing
import ZephraQuantization
import ZephraTestSupport

@testable import QwenImage21

/// Every tensor the published snapshot ships, accounted for against the module trees.
///
/// This is the cheap way to be certain a tree matches the weights it will be handed: the
/// expected names come from the configuration files and the safetensors headers say what is
/// actually in the release. A name on one side and not the other is a rename, a miscounted
/// block, or a component this port has forgotten — each of which is hours of parity debugging
/// if it is found later.
///
/// Nothing here reads a weight. Index files and headers only, so thirty-three gigabytes are
/// checked in well under a second. The per-component claims are in the `+` files beside this
/// one, and between them they account for every tensor the release ships:
///
/// | component | published | claimed |
/// | --- | --- | --- |
/// | `transformer` | 297 | all 297, `+Transformer` |
/// | `vae` | 238 | 226 as parameters and 12 named unreachable, `+VAE` |
/// | `text_encoder` | 750 | 397 decoder and 351 tower, `+TextEncoder` and `+Vision` |
///
/// The text encoder's other two are `lm_head.weight` and `model.language_model.norm.weight`,
/// named in `Qwen3VLTextWeights.omitted` and left on disk on purpose: 748 of 750 loaded.
/// One suite type, so a component's claim cannot quietly stop running while the others pass.
@Suite("Every published tensor is accounted for")
struct WeightKeyCoverageTests {
    /// The tensor names in a sharded component's index.
    static func indexedKeys(_ index: URL) throws -> Set<String> {
        struct Index: Decodable { let weightMap: [String: String] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return Set(try decoder.decode(Index.self, from: Data(contentsOf: index)).weightMap.keys)
    }

    /// Every tensor in a single-file component, by name, with its shape and none of its bytes.
    static func headerShapes(_ file: URL) throws -> [String: [Int]] {
        let header = try SafeTensorsHeader(contentsOf: file)
        return Dictionary(uniqueKeysWithValues: header.entries.map { ($0.name, $0.shape) })
    }

    /// `text_encoder/config.json` on its own, since the tower's shape is read from it long
    /// before the other four components matter.
    static func publishedTextEncoderConfiguration() throws -> Qwen3VLTextConfiguration {
        let snapshot = try #require(SnapshotUnderTest.qwenImage21.release)
        let data = try Data(contentsOf: snapshot.appending(path: "text_encoder/config.json"))
        return try JSONDecoder().decode(Qwen3VLTextConfiguration.self, from: data).validated()
    }

    /// The shapes of `named` tensors, read out of whichever shard each one lives in.
    static func shardedShapes(_ directory: URL, named: [String]) throws -> [String: [Int]] {
        struct Index: Decodable { let weightMap: [String: String] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let map = try decoder.decode(
            Index.self,
            from: Data(contentsOf: directory.appending(path: "model.safetensors.index.json"))
        ).weightMap

        var shapes: [String: [Int]] = [:]
        for shard in Set(named.compactMap { map[$0] }) {
            let header = try Self.headerShapes(directory.appending(path: shard))
            for name in named where shapes[name] == nil { shapes[name] = header[name] }
        }
        return shapes
    }
    static func expectNamesMatch(published: Set<String>, expected: Set<String>) {
        let absent = expected.subtracting(published)
        let unaccounted = published.subtracting(expected)
        #expect(absent.isEmpty, Comment(rawValue: "expected but absent: \(absent.sorted())"))
        #expect(
            unaccounted.isEmpty,
            Comment(rawValue: "present but unaccounted for: \(unaccounted.sorted())"))
    }
}
