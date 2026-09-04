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

    /// Whether the hub refused the request for want of a valid token. Every model Zephra
    /// ships is public, so this means a stale token on the Mac, not a login the model needs.
    public static func isRefusal(_ error: any Error) -> Bool {
        if case Hub.HubClientError.authorizationRequired = error { return true }
        return false
    }

    /// Whether another try could end differently. A refusal and a missing file or repository
    /// are answers, and so is any client-side status other than a timeout or a rate limit;
    /// a dropped connection, a server error, or the client's own offline verdict are what a
    /// pause and another try are for.
    public static func isPermanent(_ error: any Error) -> Bool {
        switch error {
        case Hub.HubClientError.authorizationRequired, Hub.HubClientError.fileNotFound,
             Hub.HubClientError.resourceNotFound:
            return true
        case Hub.HubClientError.httpStatusCode(let code):
            return isPermanentStatus(code)
        default:
            return false
        }
    }

    /// Any client-side status except a timeout or a rate limit. The same rule as
    /// `DownloadRetry.isPermanentStatus`, which this kit cannot import.
    static func isPermanentStatus(_ code: Int) -> Bool {
        (400..<500).contains(code) && code != 408 && code != 429
    }

    /// Why a transfer stopped, in words a person can act on: the client's offline verdict is
    /// named as such, a URL error carries the system's own sentence, and anything else keeps
    /// the message it came with.
    public static func reason(for error: any Error) -> String {
        switch error {
        case HubApi.EnvironmentError.offlineModeError:
            "This Mac is offline, or on a connection the downloader treats as metered."
        case let error as URLError:
            error.localizedDescription
        case let error as any LocalizedError:
            error.errorDescription ?? String(describing: error)
        default:
            String(describing: error)
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
