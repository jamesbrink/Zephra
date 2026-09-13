import Foundation
import Network
import ZephraLinkProtocol

/// Looking for Macs on the local network.
///
/// The whole list every time rather than a stream of arrivals and departures: a browse result
/// set is small, a phone draws the list it is given, and a diff the caller has to fold back
/// into a list is work with nothing to show for it.
public final class BonjourBrowser: @unchecked Sendable {
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "io.zephra.link.browser")
    private let lock = NSLock()
    private var subscribers: [UUID: AsyncStream<[DiscoveredHost]>.Continuation] = [:]
    private var latest: [DiscoveredHost] = []

    public init() {}

    /// Each subscriber gets its own stream. One phone shares one discovery session.
    public func results() -> AsyncStream<[DiscoveredHost]> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { sink in
            lock.withLock {
                subscribers[id] = sink
                sink.yield(latest)
                if browser == nil {
                    let browser = NWBrowser(for: .bonjourWithTXTRecord(type: BonjourRecord.type, domain: nil), using: .tcp)
                    browser.browseResultsChangedHandler = { [weak self] results, _ in
                        self?.publish(results.compactMap(Self.host))
                    }
                    self.browser = browser
                    browser.start(queue: queue)
                }
            }
            sink.onTermination = { [weak self] _ in self?.remove(id) }
        }
    }

    private func publish(_ hosts: [DiscoveredHost]) {
        lock.withLock {
            latest = hosts
            for sink in subscribers.values { sink.yield(hosts) }
        }
    }
    private func remove(_ id: UUID) {
        lock.withLock {
            subscribers[id] = nil
            if subscribers.isEmpty { browser?.cancel(); browser = nil; latest = [] }
        }
    }
    public func stop() {
        let sinks = lock.withLock {
            browser?.cancel(); browser = nil; latest = []
            let sinks = Array(subscribers.values)
            subscribers = [:]
            return sinks
        }
        for sink in sinks { sink.finish() }
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
