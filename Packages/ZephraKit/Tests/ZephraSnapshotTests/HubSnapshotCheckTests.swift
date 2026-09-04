import Foundation
import Testing
import ZephraSnapshot
import ZephraTestSupport

@Suite("A snapshot is complete only when every component the index names has arrived")
struct HubSnapshotCheckTests {
    private static let index = """
        {"_class_name": "P", "_diffusers_version": "0.36", "scheduler": ["diffusers", "S"],
         "text_encoder": ["transformers", "T"], "tokenizer": ["transformers", "K"],
         "transformer": ["diffusers", "D"], "vae": ["diffusers", "A"]}
        """

    @Test("a component the index names but the disk lacks makes the snapshot incomplete")
    func missingComponentMeansIncomplete() throws {
        let scratch = Scratch("SnapshotCheck")
        try Self.release(in: scratch, without: "vae")
        #expect(!HubSnapshotCheck.isComplete(scratch.url("snap")))
        try scratch.make("snap/vae/config.json")
        #expect(!HubSnapshotCheck.isComplete(scratch.url("snap")), "a config is a module, and a module needs weights")
        try scratch.make("snap/vae/diffusion_pytorch_model.safetensors")
        #expect(HubSnapshotCheck.isComplete(scratch.url("snap")))
    }

    @Test("a numbered shard implies its siblings, with or without an index file")
    func numberedShardsImplyTheirSiblings() throws {
        let scratch = Scratch("SnapshotCheck")
        try Self.release(in: scratch, without: "text_encoder")
        try scratch.make("snap/text_encoder/config.json")
        try scratch.make("snap/text_encoder/model-00001-of-00002.safetensors")
        #expect(!HubSnapshotCheck.isComplete(scratch.url("snap")))
        try scratch.make("snap/text_encoder/model-00002-of-00002.safetensors")
        #expect(HubSnapshotCheck.isComplete(scratch.url("snap")))
    }

    @Test("an hf-layout snapshot of links into the blob store is judged the same way")
    func linkedSnapshotIsJudgedByWhatItLinks() throws {
        let scratch = Scratch("SnapshotCheck")
        try scratch.write(Self.index, to: "repo/blobs/index")
        try scratch.make("repo/blobs/weights")
        try scratch.link("repo/snapshots/a/model_index.json", to: "../../blobs/index")
        for component in ["scheduler", "tokenizer"] {
            try scratch.link("repo/snapshots/a/\(component)/config.txt", to: "../../../blobs/weights")
        }
        for module in ["transformer", "text_encoder", "vae"] {
            try scratch.link("repo/snapshots/a/\(module)/config.json", to: "../../../blobs/weights")
        }
        try scratch.link("repo/snapshots/a/transformer/model.safetensors", to: "../../../blobs/weights")
        try scratch.link("repo/snapshots/a/vae/model.safetensors", to: "../../../blobs/weights")
        #expect(!HubSnapshotCheck.isComplete(scratch.url("repo/snapshots/a")), "text_encoder has no weights yet")
        try scratch.link("repo/snapshots/a/text_encoder/model.safetensors", to: "../../../blobs/weights")
        #expect(HubSnapshotCheck.isComplete(scratch.url("repo/snapshots/a")))
    }

    @Test("a repository that is one module, config beside weights, still counts")
    func singleModuleRepositoryCounts() throws {
        let scratch = Scratch("SnapshotCheck")
        try scratch.make("snap/config.json")
        #expect(!HubSnapshotCheck.isComplete(scratch.url("snap")))
        try scratch.make("snap/model.safetensors")
        #expect(HubSnapshotCheck.isComplete(scratch.url("snap")))
    }

    /// A complete diffusers-style release under `snap/`, minus one component.
    private static func release(in scratch: Scratch, without missing: String) throws {
        try scratch.write(index, to: "snap/model_index.json")
        let files = [
            "scheduler/scheduler_config.json", "tokenizer/tokenizer.json",
            "transformer/config.json", "transformer/model.safetensors",
            "text_encoder/config.json", "text_encoder/model.safetensors",
            "vae/config.json", "vae/diffusion_pytorch_model.safetensors",
        ]
        for file in files where !file.hasPrefix(missing + "/") {
            try scratch.make("snap/\(file)")
        }
    }
}
