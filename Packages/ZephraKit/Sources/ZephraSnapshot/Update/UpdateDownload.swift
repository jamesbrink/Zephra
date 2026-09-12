import Foundation
import ZephraCore

/// Fetches a published release's disk image and hands back the file, once its SHA-256 is the
/// one the manifest names.
///
/// The image is a few hundred megabytes, so the body is streamed to disk through the same
/// `ChunkedDownload` a model transfer uses, with its back pressure and its check for
/// cancellation between chunks. It lands as `<build>.dmg.incomplete` and is renamed only after
/// the digest matches, so nothing anywhere else ever sees a half-written or unverified disk
/// image under the name the installer opens.
///
/// Deliberately no resume: a release is one file that takes a minute, not thirteen gigabytes
/// of shards, and a `Range` against a mutable CDN object is a whole second correctness problem
/// for that minute. A broken transfer starts the file over, up to `DownloadRetry.attempts`
/// times. See ROADMAP, "Updates: left out on purpose".
public struct UpdateDownload: Sendable {
    private let configuration: URLSessionConfiguration

    /// Creates a downloader. A test passes a configuration carrying a `URLProtocol` stub and
    /// gets the whole thing with no network at all.
    public init(configuration: URLSessionConfiguration = UpdateDownload.defaultConfiguration()) {
        self.configuration = configuration
    }

    /// Fetches `manifest`'s image into `directory` and returns the verified file.
    ///
    /// `onProgress` is a fraction of the whole, and reaches 1 exactly once, as the file is
    /// renamed into place: a progress bar that stops at 0.98 because the last chunk was the
    /// digest's is a bar that looks stuck.
    public func fetch(
        _ manifest: ReleaseManifest,
        into directory: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appending(path: "Zephra-\(manifest.build).dmg")
        let partial = target.appendingPathExtension("incomplete")
        try await DownloadRetry.run(isPermanent: { ($0 as? UpdateDownloadError)?.isPermanent ?? false }) {
            try await transfer(manifest, to: partial, onProgress: onProgress)
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: partial, to: target)
        onProgress(1)
        return target
    }

    /// One attempt: the whole body written from nothing, then verified. A partial left by a
    /// broken try is removed first rather than appended to, since there is no resume.
    private func transfer(
        _ manifest: ReleaseManifest, to partial: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: partial)
        let session = URLSession(configuration: configuration, delegate: ChunkedDownload(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let delegate = session.delegate as? ChunkedDownload else {
            throw UpdateDownloadError.interrupted(reason: "The download session was not set up.")
        }
        var request = URLRequest(url: manifest.url)
        request.setValue(ModelDownloader.defaultUserAgent(), forHTTPHeaderField: "User-Agent")
        let response: HTTPURLResponse
        let chunks: ChunkedBody
        do {
            (response, chunks) = try await delegate.start(request, on: session)
        } catch {
            try Task.checkCancellation()
            throw UpdateDownloadError.interrupted(reason: error.localizedDescription)
        }
        guard response.statusCode == 200 else {
            throw UpdateDownloadError.refused(status: response.statusCode)
        }
        let expected = response.expectedContentLength
        try await write(chunks, to: partial, of: expected, onProgress: onProgress)
        guard try FileDigest.sha256(of: partial).lowercased() == manifest.sha256.lowercased() else {
            try? FileManager.default.removeItem(at: partial)
            throw UpdateDownloadError.checksumMismatch
        }
    }

    /// Writes the body as it arrives, reporting a fraction whenever the server said how much
    /// there is to come. A server that did not say leaves the bar at 0 until the rename, which
    /// is honest: a made-up denominator is worse than none.
    private func write(
        _ chunks: ChunkedBody, to partial: URL, of expected: Int64,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        FileManager.default.createFile(atPath: partial.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        var written: Int64 = 0
        do {
            for try await chunk in chunks {
                try Task.checkCancellation()
                try handle.write(contentsOf: chunk)
                written += Int64(chunk.count)
                if expected > 0 { onProgress(min(Double(written) / Double(expected), 1)) }
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            try Task.checkCancellation()
            throw UpdateDownloadError.interrupted(reason: error.localizedDescription)
        }
        try handle.synchronize()
        guard expected <= 0 || written == expected else {
            throw UpdateDownloadError.interrupted(
                reason: "The download ended at \(written) bytes of \(expected).")
        }
    }

    /// Where a release being fetched lives: `<Application Support>/Zephra/Updates`, which
    /// `UpdateChecker` empties at the next launch.
    public static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return support.appending(path: "Zephra/Updates")
    }

    /// A session configuration for one large transfer: no response cache at all, and a stalled
    /// connection giving up in a minute so the retry can start over.
    public static func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.waitsForConnectivity = true
        return configuration
    }
}
