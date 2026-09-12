import Foundation
import Network
import ZephraLinkClient
import os

/// The phone noticing that it is on a different network, and doing the one thing that is worth
/// doing about it.
///
/// Two failures this answers, both of them the same moment from either side. A phone that walks
/// out of the house sits out a thirty-second wait it was given for a Mac that was asleep, when
/// the truth is it has just joined a network the Mac can be reached over. And a phone that
/// leaves Wi-Fi mid-session keeps the socket it had — the interface is gone, nothing arrives,
/// and neither end is told — so the session looks live until somebody presses something.
///
/// `NWPathMonitor` is what says so, and the decision over it is `reaction(from:to:isLive:)`,
/// which is pure and pinned by `LinkPathWatchTests`. The monitor itself is exercised by hand,
/// on a phone, by turning Wi-Fi off.
@MainActor
final class LinkPathWatch {
    private let client: LinkClient
    private let reconnect: LinkReconnect
    /// Made afresh by every `start()`: a cancelled `NWPathMonitor` cannot be started again.
    private var monitor: NWPathMonitor?
    /// The path as of the last report, or nil before the first one.
    private var mark: LinkPathMark?
    private let logger = Logger(subsystem: "io.zephra", category: "mobile.path")

    /// A watch over one client and the policy that dials for it.
    init(client: LinkClient, reconnect: LinkReconnect) {
        self.client = client
        self.reconnect = reconnect
    }

    /// Starts watching, or does nothing if it already is.
    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let mark = LinkPathMark(path)
            Task { @MainActor in self?.react(to: mark) }
        }
        monitor.start(queue: DispatchQueue(label: "io.zephra.link.path"))
    }

    /// Stops watching, which the app does the moment it goes to the background: a phone in a
    /// pocket is not about to act on a change of network.
    func stop() {
        monitor?.cancel()
        monitor = nil
        mark = nil
    }

    /// What to do about one path, and the doing of it.
    private func react(to mark: LinkPathMark) {
        let reaction = Self.reaction(from: self.mark, to: mark, isLive: client.connection.isLive)
        self.mark = mark
        switch reaction {
        case .nothing:
            break
        case .redial:
            logger.notice("The network path changed; dialling the Mac now.")
            reconnect.retryNow()
        case .probe:
            logger.notice("The network path changed under a live session; asking the Mac.")
            Task { await client.probe() }
        }
    }

    /// What a path is worth doing about, given the one before it.
    ///
    /// The first report is nothing to act on: the app has just come to the front and is already
    /// dialling, and a redial on top of that is the same attempt twice. A path that carries
    /// nothing is nothing to act on either — no road would open over it, and the wait that is
    /// running is the right thing to be doing. What is left is a path that is different and can
    /// carry something, and there the answer depends on whether there is a session: a live one
    /// may be a ghost, so it is asked; anything else is dialled at once, which covers the wait
    /// after a failure, a Mac that turned this phone away, and being plainly offline.
    static func reaction(
        from previous: LinkPathMark?, to current: LinkPathMark, isLive: Bool
    ) -> LinkPathReaction {
        guard let previous, previous != current, current.isSatisfied else { return .nothing }
        return isLive ? .probe : .redial
    }
}
