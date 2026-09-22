import Foundation
import Testing
import ZephraCore
import ZephraTestSupport

@testable import ZephraSnapshot

extension ModelDownloaderTests {
    @Test("cancelling a model removes its unfinished repository, including during retry backoff",
          arguments: [false, true])
    func cancellationDiscardsDownload(backoff: Bool) async throws {
        let scratch = Scratch("CancelDownload")
        let model = ModelCatalog.zImageTurbo8bit
        guard case .huggingFace(let repo, _, _) = model.source else { return }
        let locations = ModelLocations(root: scratch.url("models"))
        let destination = locations.downloads(repoID: repo)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appending(path: "model.safetensors.incomplete"))
        try Data("etag".utf8).write(to: destination.appending(path: "model.safetensors.incomplete.etag"))
        try Data("{}".utf8).write(to: destination.appending(path: "config.json"))
        let listing = try JSONSerialization.data(withJSONObject: [
            ["type": "file", "path": "model.safetensors", "size": 10]
        ])
        StubHub.reset(StubHub.Behaviour(
            pages: [listing], files: ["model.safetensors": Data(repeating: 7, count: 10)],
            truncatesTo: backoff ? 2 : nil, pause: backoff ? 0 : 10))
        let downloader = ModelDownloader(configuration: StubHub.configuration())
        let task = Task {
            try await downloader.fetch(model, into: locations, onProgress: { _ in })
        }
        defer { task.cancel() }
        try await waitForFileRequest()
        if backoff { try await Task.sleep(for: .milliseconds(100)) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: destination.path))

        StubHub.reset(StubHub.Behaviour(
            pages: [listing], files: ["model.safetensors": Data(repeating: 7, count: 10)]))
        _ = try await downloader.fetch(model, into: locations, onProgress: { _ in })
        #expect(StubHub.records.filter { $0.path.contains("/resolve/") }.allSatisfy { $0.range == nil })
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "model.safetensors").path))
    }

    @Test("cleanup preserves completed repositories and refuses linked destinations")
    func cancellationCleanupBoundaries() throws {
        let scratch = Scratch("CancelBoundaries")
        try scratch.write("sha", to: "models/complete/.zephra-commit")
        try scratch.write("keep", to: "models/complete/model.safetensors")
        try scratch.write("partial", to: "outside/model.safetensors.incomplete")
        try FileManager.default.createSymbolicLink(
            at: scratch.url("models/linked"), withDestinationURL: scratch.url("outside"))
        let complete = RepositoryDownload(repoID: "org/complete", patterns: ["*"], destination: scratch.url("models/complete"))
        try ModelDownloader.discardUnfinished([complete], under: scratch.url("models"))
        #expect(scratch.hasFile("models/complete/model.safetensors"))
        try scratch.write("sha", to: "models/complete/.zephra-revision")
        try scratch.write("part", to: "models/complete/adapter.safetensors.incomplete")
        try scratch.write("etag", to: "models/complete/adapter.safetensors.incomplete.etag")
        try ModelDownloader.discardUnfinished([complete], under: scratch.url("models"))
        #expect(scratch.hasFile("models/complete/model.safetensors"))
        #expect(scratch.hasFile("models/complete/.zephra-commit"))
        #expect(!scratch.hasFile("models/complete/.zephra-revision"))
        #expect(!scratch.hasFile("models/complete/adapter.safetensors.incomplete"))
        #expect(!scratch.hasFile("models/complete/adapter.safetensors.incomplete.etag"))
        let linked = RepositoryDownload(repoID: "org/linked", patterns: ["*"], destination: scratch.url("models/linked"))
        #expect(throws: ModelDownloadError.self) {
            try ModelDownloader.discardUnfinished([linked], under: scratch.url("models"))
        }
        #expect(scratch.hasFile("outside/model.safetensors.incomplete"))
    }

    private func waitForFileRequest() async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !StubHub.records.contains(where: { $0.path.contains("/resolve/") }) {
            guard ContinuousClock.now < deadline else {
                throw ModelDownloadError.interrupted(reason: "The test download did not start")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
