import Foundation

/// Reads `releases/latest.json` and says what the newest published Zephra is.
///
/// One request, no cache, no waiting for connectivity. The manifest is a hundred bytes behind
/// a CloudFront distribution told to hold it for a minute and revalidate, so the only caching
/// that matters is the one on this side: a `URLCache` answering a launch check with last
/// week's manifest would leave a Mac permanently one build behind with nothing on screen to
/// say so. The session is ephemeral, its cache is nil, the policy ignores whatever is local,
/// and the request carries `Cache-Control: no-cache` for any proxy between here and the
/// bucket.
///
/// `waitsForConnectivity` is off on purpose: a check is a background errand, and one that sits
/// waiting for a network to come back would fire hours later, at a moment nobody asked about.
/// Offline is an answer — `unreachable` — and the next check is six hours away in any case.
public struct UpdateFeed: Sendable {
    /// Where the publish script writes the manifest.
    public static let production = URL(string: "https://zephra-assets.urandom.io/releases/latest.json")!

    /// How long the whole errand may take before it is called unreachable.
    public static let timeout: TimeInterval = 15

    /// The manifest to read.
    public let url: URL
    private let configuration: URLSessionConfiguration

    /// Creates a feed. The defaults are the published manifest; a test passes a configuration
    /// carrying a `URLProtocol` stub and gets the whole thing with no network at all.
    public init(
        url: URL = UpdateFeed.production,
        configuration: URLSessionConfiguration = UpdateFeed.defaultConfiguration()
    ) {
        self.url = url
        self.configuration = configuration
    }

    /// The newest published release, or why it could not be read.
    public func latest() async throws -> ReleaseManifest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(ModelDownloader.defaultUserAgent(), forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw UpdateFeedError.unreachable(reason: error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateFeedError.refused(status: status) }
        do {
            return try JSONDecoder().decode(ReleaseManifest.self, from: data)
        } catch {
            throw UpdateFeedError.malformed
        }
    }

    /// A session configuration for one small, uncacheable request.
    public static func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        return configuration
    }
}
