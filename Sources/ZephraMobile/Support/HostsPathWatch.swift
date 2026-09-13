import Foundation
import Network

/// One system path monitor wakes every enabled host's independent recovery policy.
@MainActor
final class HostsPathWatch {
    private var monitor: NWPathMonitor?
    private var task: Task<Void, Never>?
    func start(_ hosts: HostConnections) {
        guard monitor == nil else { return }
        let (stream, sink) = AsyncStream<LinkPathMark>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { sink.yield(LinkPathMark($0)) }
        monitor.start(queue: DispatchQueue(label: "io.zephra.hosts.path"))
        self.monitor = monitor
        task = Task { [weak hosts] in
            var previous: LinkPathMark?
            var lastAction: Date?
            for await mark in stream {
                guard let hosts, !Task.isCancelled else { return }
                for host in hosts.hosts where host.preference.enabled {
                    switch LinkPathWatch.reaction(from: previous, to: mark,
                        isLive: host.client.connection.isLive, lastAction: lastAction) {
                    case .nothing: break
                    case .redial: host.reconnect?.retryNow()
                    case .probe: Task { await host.client.probe() }
                    }
                }
                if previous != nil && previous != mark && mark.isSatisfied { lastAction = Date() }
                previous = mark
            }
        }
    }
    func stop() {
        monitor?.cancel(); monitor = nil
        task?.cancel(); task = nil
    }
}
