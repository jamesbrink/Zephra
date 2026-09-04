import Foundation
import Testing
import ZephraSnapshot
import ZephraTestSupport

@Suite("The hub client's flat layout")
struct HubFlatLayoutTests {
    /// Where the app's hub client puts `acme/weights`.
    private static let flat = "models/acme/weights"

    @Test("a model the app downloaded is recognised on the next launch")
    func flatLayoutIsASnapshot() throws {
        let scratch = Scratch("HubFlat")
        try scratch.make("\(Self.flat)/model_index.json")
        try scratch.make("\(Self.flat)/transformer/model.safetensors")
        #expect(
            HubCache.snapshot(of: "acme/weights", in: scratch.root)?.standardizedFileURL.path
                == scratch.url(Self.flat).standardizedFileURL.path,
            "the flat directory is its own snapshot"
        )
    }

    @Test("a transfer still in flight is not a model yet")
    func incompleteFilesMeanNotYet() throws {
        let scratch = Scratch("HubFlat")
        try scratch.make("\(Self.flat)/model_index.json")
        try scratch.make("\(Self.flat)/vae/model.safetensors")
        try scratch.make(
            "\(Self.flat)/.cache/huggingface/download/transformer/model.safetensors.abc.incomplete")
        #expect(HubCache.snapshot(of: "acme/weights", in: scratch.root) == nil)
        #expect(HubSnapshotCheck.incompleteFiles(in: scratch.url(Self.flat)).count == 1)
    }

    @Test("a shard the index names but the disk lacks makes the snapshot incomplete")
    func missingShardMeansNotYet() throws {
        let scratch = Scratch("HubFlat")
        try scratch.make("\(Self.flat)/model_index.json")
        try scratch.make("\(Self.flat)/transformer/model-00001-of-00002.safetensors")
        try scratch.write(
            #"{"weight_map": {"a": "model-00001-of-00002.safetensors", "b": "model-00002-of-00002.safetensors"}}"#,
            to: "\(Self.flat)/transformer/model.safetensors.index.json")
        #expect(HubCache.snapshot(of: "acme/weights", in: scratch.root) == nil)

        try scratch.make("\(Self.flat)/transformer/model-00002-of-00002.safetensors")
        #expect(HubCache.snapshot(of: "acme/weights", in: scratch.root) != nil)
    }

    @Test("the hf layout answers first when both are there")
    func hubLayoutWins() throws {
        let scratch = Scratch("HubFlat")
        try scratch.make("\(Self.flat)/model_index.json")
        try scratch.make("\(Self.flat)/vae/model.safetensors")
        let hub = "models--acme--weights/snapshots/abc"
        try scratch.make("\(hub)/model_index.json")
        try scratch.make("\(hub)/vae/model.safetensors")
        #expect(
            HubCache.snapshot(of: "acme/weights", in: scratch.root)?.lastPathComponent == "abc")
        #expect(HubCache.repositories(of: "acme/weights", in: scratch.root).count == 2)
    }
}
