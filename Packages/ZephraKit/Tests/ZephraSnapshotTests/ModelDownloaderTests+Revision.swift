import Foundation
import Testing
import ZephraCore
import ZephraTestSupport

@testable import ZephraSnapshot

extension ModelDownloaderTests {
    @Test("a requested-revision file with a trailing newline still resumes at the pin")
    func requestedRevisionIsTrimmed() async throws {
        let scratch = Scratch("DownloadRevision")
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("model_index.json", 2)])], files: ["model_index.json": Data("{}".utf8)],
                sha: "second"))
        try scratch.write("first", to: "models/.zephra-revision")
        // Written by hand, or by an editor that adds one: the file names the branch, then a newline.
        try scratch.write("v1\n", to: "models/.zephra-requested-revision")

        _ = try await downloader().download(
            repoID: "org/repo", revision: "v1", patterns: ["*"], into: scratch.url("models"),
            onProgress: { _ in })

        let paths = StubHub.records.map(\.path)
        #expect(paths.contains("/api/models/org/repo/tree/first"), "listed at the pinned commit")
        #expect(!paths.contains { $0.contains("/revision/") }, "the branch was not asked again")
    }
}
