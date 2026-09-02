import Foundation
import Testing
import ZephraCore

@testable import ZephraBackendZImage

@Suite("ZImage availability")
struct ZImageAvailabilityTests {
    /// A throwaway directory, removed when the test's value goes out of scope.
    final class Scratch {
        let root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "ZImageAvailability-\(UUID().uuidString)", directoryHint: .isDirectory)

        deinit { try? FileManager.default.removeItem(at: root) }

        /// Creates `path` under the scratch root, as a directory or as an empty file.
        @discardableResult
        func make(_ path: String, isDirectory: Bool = false) throws -> URL {
            let url = root.appending(path: path)
            let files = FileManager.default
            try files.createDirectory(
                at: isDirectory ? url : url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !isDirectory { try Data().write(to: url) }
            return url
        }
    }

    @Test("the hub cache honours HF_HUB_CACHE first, then HF_HOME")
    func cacheDirectoryFollowsTheEnvironment() {
        #expect(
            ZImageHubCache.directory(environment: ["HF_HUB_CACHE": "/cache/hub"]).path
                == "/cache/hub"
        )
        #expect(
            ZImageHubCache.directory(environment: ["HF_HOME": "/hf"]).path == "/hf/hub"
        )
        #expect(
            ZImageHubCache.directory(
                environment: ["HF_HUB_CACHE": "/cache/hub", "HF_HOME": "/hf"]
            ).path == "/cache/hub"
        )
        #expect(
            ZImageHubCache.directory(environment: [:]).path
                .hasSuffix("/.cache/huggingface/hub")
        )
    }

    @Test("a cached snapshot is found only once it has a config and weights")
    func snapshotNeedsConfigAndWeights() throws {
        let scratch = Scratch()
        let snapshot = "models--mzbac--Z-Image-Turbo-8bit/snapshots/abc123"
        try scratch.make("\(snapshot)/model_index.json")
        #expect(
            ZImageHubCache.snapshot(of: "mzbac/Z-Image-Turbo-8bit", in: scratch.root) == nil,
            "a config with no weights is an abandoned download, not a model"
        )

        try scratch.make("\(snapshot)/transformer/model.safetensors")
        #expect(ZImageHubCache.snapshot(of: "mzbac/Z-Image-Turbo-8bit", in: scratch.root) != nil)
    }

    @Test("nothing cached at all reads as a download of the descriptor's size")
    func nothingCachedNeedsADownload() async throws {
        let scratch = Scratch()
        try FileManager.default.createDirectory(at: scratch.root, withIntermediateDirectories: true)
        #expect(ZImageHubCache.snapshot(of: "example/absent", in: scratch.root) == nil)
    }

    @Test("a local directory that was never built is missing, and says what it lacks")
    func localDirectoryThatIsNotThere() async throws {
        let scratch = Scratch()
        let descriptor = Self.local(at: scratch.root.appending(path: "never-built"))
        let availability = await ZImageBackend().availability(of: descriptor)
        #expect(availability.isObtainable == false)
        #expect(availability.label == "Not built yet")
        #expect(availability.reason?.contains("model_index.json") == true)
    }

    @Test("a local directory with every entry the loader opens is available")
    func localDirectoryThatIsComplete() async throws {
        let scratch = Scratch()
        try scratch.make("built/model_index.json")
        for part in ["transformer", "text_encoder", "vae"] {
            try scratch.make("built/\(part)", isDirectory: true)
        }
        let descriptor = Self.local(at: scratch.root.appending(path: "built"))
        #expect(await ZImageBackend().availability(of: descriptor) == .available)
    }

    /// The catalog's default model, pointed at a local directory instead of the hub.
    private static func local(at directory: URL) -> ModelDescriptor {
        let base = ModelCatalog.default
        return ModelDescriptor(
            id: "local-test",
            displayName: base.displayName,
            variantName: base.variantName,
            backend: base.backend,
            source: .localDirectory(directory),
            quantization: base.quantization,
            downloadBytes: 0,
            residentBytes: base.residentBytes,
            maxPromptTokens: base.maxPromptTokens,
            capabilities: base.capabilities
        )
    }
}
