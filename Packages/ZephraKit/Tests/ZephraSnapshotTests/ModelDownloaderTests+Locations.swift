import Foundation
import Testing
import ZephraCore
import ZephraTestSupport

@testable import ZephraSnapshot

extension ModelDownloaderTests {
    @Test("a fresh downloader writes only to the selected root despite partial files in the previous root")
    func freshDownloadHonoursSelectedRoot() async throws {
        let scratch = Scratch("DownloadLocation")
        let model = ModelCatalog.zImageTurbo8bit
        guard case .huggingFace(let repo, _, _) = model.source else { return }
        let old = ModelLocations(root: scratch.url("old"))
        let partial = old.downloads(repoID: repo).appending(path: "model.safetensors.incomplete")
        try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old partial".utf8).write(to: partial)
        let listing = try JSONSerialization.data(withJSONObject: [
            ["type": "file", "path": "model.safetensors", "size": 4]
        ])
        StubHub.reset(StubHub.Behaviour(pages: [listing], files: ["model.safetensors": Data("new!".utf8)]))
        let downloader = ModelDownloader(configuration: StubHub.configuration())
        let selected = ModelLocations(root: scratch.url("external"), previous: [old.root])
        let result = try await downloader.fetch(model, into: selected, onProgress: { _ in })
        #expect(result == selected.downloads(repoID: repo))
        #expect(try Data(contentsOf: result.appending(path: "model.safetensors")) == Data("new!".utf8))
        #expect(try Data(contentsOf: partial) == Data("old partial".utf8))
        #expect(!FileManager.default.fileExists(atPath: old.downloads(repoID: repo).appending(path: "model.safetensors").path))
    }

    @Test("an unavailable external disk fails without creating a substitute directory")
    func missingExternalDiskIsNotRecreated() throws {
        let path = URL(filePath: "/Volumes/Zephra-Missing-\(UUID().uuidString)/Models")
        #expect(throws: ModelDirectoryError.self) { try ModelDirectoryAccess.prepare(path) }
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }
    @Test("mounted volume URLs with directory hints match the chosen external folder")
    func mountedVolumeDirectoryHint() throws {
        try ModelDirectoryAccess.requireMountedVolume(
            containing: URL(filePath: "/Volumes/Example/Models"),
            mounted: [URL(filePath: "/Volumes/Example/", directoryHint: .isDirectory)])
    }

}
