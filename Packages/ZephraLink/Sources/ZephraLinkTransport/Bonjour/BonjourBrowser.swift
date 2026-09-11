import Foundation
import Network
import ZephraLinkProtocol

/// Looking for Macs on the local network.
///
/// The whole list every time rather than a stream of arrivals and departures: a browse result
/// set is small, a phone draws the list it is given, and a diff the caller has to fold back
/// into a list is work with nothing to show for it.
public final class BonjourBrowser: @unchecked Sendable {
    private let browser: NWBrowser
    private let queue = DispatchQueue(label: "io.zephra.link.browser")
    private let stream: AsyncStream<[DiscoveredHost]>
    private let continuation: AsyncStream<[DiscoveredHost]>.Continuation

    /// A browser for `_zephra._tcp`, which starts on the first call to `results()`.
    public init() {
        browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: BonjourRecord.type, domain: nil),
            using: .tcp)
        (stream, continuation) = AsyncStream.makeStream()
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.continuation.yield(results.compactMap(Self.host))
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.continuation.finish() }
        }
    }

    /// The Macs on the network, as the list changes.
    public func results() -> AsyncStream<[DiscoveredHost]> {
        browser.start(queue: queue)
        return stream
    }

    /// Stops looking.
    public func stop() {
        browser.cancel()
        continuation.finish()
    }

    /// A road to one of them, connected and ready.
    public func connect(_ host: DiscoveredHost, timeout: Duration = .seconds(10)) async throws
        -> TCPConnection
    {
        let connection = TCPConnection(connection: NWConnection(to: host.endpoint, using: .tcp))
        do {
            try await connection.start(timeout: timeout)
        } catch {
            await connection.close()
            throw error
        }
        return connection
    }

    /// One browse result as a host, or nil where it is not a named service.
    private static func host(_ result: NWBrowser.Result) -> DiscoveredHost? {
        guard case .service(let name, _, _, _) = result.endpoint else { return nil }
        return DiscoveredHost(
            name: name, roomID: BonjourRecord.room(in: result.metadata), endpoint: result.endpoint)
    }
}
