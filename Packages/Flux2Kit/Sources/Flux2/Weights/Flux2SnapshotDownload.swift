import Foundation
import Hub

/// Fetching the release from the Hugging Face hub, into the same cache `hf download` fills.
///
/// Zephra's other downloading family goes through code vendored with its pipeline, which this
/// family cannot import without linking that pipeline too. So the download lives here, forty
/// lines over the hub client the tokenizer already depends on. When a second family needs it,
/// this is the file to lift into a package of its own.
public enum Flux2SnapshotDownload {
    /// One progress update: how much of the transfer is done, and how fast it is moving.
    public struct Progress: Sendable {
        /// Files finished so far.
        public let completedFiles: Int
        /// Files the download covers.
        public let totalFiles: Int
        /// Completion from 0 to 1.
        public let fraction: Double
        /// Transfer rate, once there has been enough of one to measure.
        public let bytesPerSecond: Double?
    }

    /// Resolves `repoID` at `revision` to a local snapshot directory, transferring only the
    /// files matching `patterns` and only those the cache does not already hold.
    ///
    /// The cache is the hub client's own, under `HF_HUB_CACHE`, `HF_HOME`, or the default,
    /// which is what lets `make prefetch-flux2` seed it ahead of a first launch.
    public static func snapshot(
        repoID: String,
        revision: String,
        patterns: [String],
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        let hub = HubApi(downloadBase: cacheDirectory())
        let repo = Hub.Repo(id: repoID)
        return try await hub.snapshot(from: repo, revision: revision, matching: patterns) { progress, rate in
            onProgress(
                Progress(
                    completedFiles: Int(progress.completedUnitCount),
                    totalFiles: Int(progress.totalUnitCount),
                    fraction: progress.fractionCompleted,
                    bytesPerSecond: rate))
        }
    }

    /// Where the hub cache lives, honouring the same variables the `hf` tool honours.
    static func cacheDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let hubCache = environment["HF_HUB_CACHE"], !hubCache.isEmpty {
            return URL(filePath: hubCache)
        }
        if let home = environment["HF_HOME"], !home.isEmpty {
            return URL(filePath: home).appending(path: "hub")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cache/huggingface/hub")
    }
}
