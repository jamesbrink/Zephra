import Foundation
import ZephraCore

/// Fetches a model repository from Hugging Face into a folder Zephra owns.
///
/// Plain anonymous HTTPS and nothing else: the tree endpoint says what is in the repository,
/// `/resolve/` serves each file, and the files land flat in the destination exactly as the
/// repository names them. There is no cache layout to honour, no `hf` tool to have installed,
/// and no token — every repository the catalog names is public, and an `Authorization` header
/// is never sent, so a stale token on the Mac cannot turn a public model into a login wall.
///
/// A file being transferred is `<name>.incomplete` beside where it will live, and it is renamed
/// only when its size matches what the listing said. So a download that is stopped, or that
/// breaks, resumes from the bytes already there — `Range` on the next request — and a truncated
/// file is never mistaken for a finished one.
public struct ModelDownloader: Sendable {
    /// The only host these releases come from.
    public static let huggingFace = URL(string: "https://huggingface.co")!

    /// Where the repository is read from.
    public let host: URL
    /// What Zephra calls itself in the request, so the hub's logs say who asked.
    public let userAgent: String
    let configuration: URLSessionConfiguration

    /// Creates a downloader. The defaults are the real hub; a test passes a configuration
    /// carrying a `URLProtocol` stub and gets the whole thing with no network at all.
    public init(
        host: URL = ModelDownloader.huggingFace,
        userAgent: String = ModelDownloader.defaultUserAgent(),
        configuration: URLSessionConfiguration = ModelDownloader.defaultConfiguration()
    ) {
        self.host = host
        self.userAgent = userAgent
        self.configuration = configuration
    }

    /// Fetches every file in `repoID` matching `patterns` into `destination`, resuming whatever
    /// is part-way, and returns `destination`.
    ///
    /// Progress is weighted by bytes and counts what was already on disk, so a resumed download
    /// starts where it left off rather than at zero. Cancellation is checked between chunks and
    /// leaves the `.incomplete` files behind on purpose: they are what the next try continues
    /// from.
    public func download(
        repoID: String,
        revision: String = "main",
        patterns: [String],
        into destination: URL,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        let session = makeSession()
        defer { session.finishTasksAndInvalidate() }
        let files = try await listing(of: repoID, revision: revision, on: session)
            .filter { FilePattern.matchesAny($0.path, patterns: patterns) }
        guard !files.isEmpty else { throw ModelDownloadError.repositoryNotFound(repoID: repoID) }

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var tally = DownloadTally(
            totalFiles: files.count, totalBytes: files.reduce(0) { $0 + $1.bytes })
        for file in files { tally.advance(by: bytesOnDisk(of: file, in: destination)) }
        if let event = tally.report(force: true) { onProgress(event) }

        for file in files {
            try Task.checkCancellation()
            try await fetch(
                file, from: repoID, revision: revision, into: destination, on: session,
                tally: &tally, onProgress: onProgress)
            tally.finishFile()
            if let event = tally.report(force: true) { onProgress(event) }
        }
        return destination
    }

    /// What Zephra calls itself: the bundle's version when there is a bundle, and the bare name
    /// in a tool that has none.
    public static func defaultUserAgent() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        return "Zephra/\((version as? String) ?? "dev")"
    }

    /// A session configuration for transfers that are measured in gigabytes: no response cache
    /// at all, and a resource timeout long enough for the whole thing on a slow line, while a
    /// stalled connection still gives up in a minute so the retry can start over.
    public static func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.waitsForConnectivity = true
        return configuration
    }

    /// A session and the delegate that streams its bodies. One per download, invalidated when
    /// it is done: a session holds its delegate, and a leaked pair per transfer is a leak per
    /// model.
    func makeSession() -> URLSession {
        URLSession(
            configuration: configuration, delegate: ChunkedDownload(), delegateQueue: nil)
    }

    /// A request with Zephra's user agent and deliberately no `Authorization` header.
    func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// How much of `file` is already there: the whole thing when it is in place at the right
    /// size, or what a stopped transfer left in its `.incomplete` file.
    func bytesOnDisk(of file: RepositoryFile, in destination: URL) -> Int64 {
        let target = destination.appending(path: file.path)
        if let size = Self.size(of: target), file.bytes == 0 || size == file.bytes { return size }
        return Self.size(of: Self.partial(of: target)) ?? 0
    }

    /// The file a transfer writes into until it is whole.
    static func partial(of target: URL) -> URL {
        target.appendingPathExtension("incomplete")
    }

    /// A file's size, or nil when it is not there.
    ///
    /// Asked of the file system rather than through `URL.resourceValues`, which caches what it
    /// read: the same path is measured before a transfer and again after it, and a cached
    /// answer would report the file that was there when it started.
    static func size(of url: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false))
        return (attributes?[.size] as? NSNumber)?.int64Value
    }
}
