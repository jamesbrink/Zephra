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
    /// How close together two reports have to be for the second to be the same change.
    ///
    /// A handover from Wi-Fi to cellular is not one report: the system says the path is gone,
    /// then that it is back over something else, then that it has settled, inside a second.
    /// Acting on each of those is a dial that cancels the dial before it, over and over, so the
    /// phone spends the handover starting attempts and finishing none.
    static let coalesce: Duration = .seconds(1)

    private let client: LinkClient
    private let reconnect: LinkReconnect
    /// Made afresh by every `start()`: a cancelled `NWPathMonitor` cannot be started again.
    private var monitor: NWPathMonitor?
    /// The reports, in the order they were made. The system reports on a queue of its own, and
    /// a task per report is two hops to the main actor that can land the other way round —
    /// which would leave `mark` holding the older path and the next change measured against it.
    private var reports: AsyncStream<LinkPathMark>.Continuation?
    private var drain: Task<Void, Never>?
    /// The path as of the last report, or nil before the first one.
    private var mark: LinkPathMark?
    /// When something was last done about a change, for the damping above.
    private var lastAction: Date?
    private let logger = Logger(subsystem: "io.zephra", category: "mobile.path")

    /// A watch over one client and the policy that dials for it.
    init(client: LinkClient, reconnect: LinkReconnect) {
        self.client = client
        self.reconnect = reconnect
    }

    /// Starts watching, or does nothing if it already is.
    func start() {
        guard monitor == nil else { return }
        let (stream, sink) = AsyncStream<LinkPathMark>.makeStream()
        reports = sink
        drain = Task { [weak self] in
            for await mark in stream {
                guard let self else { return }
                self.react(to: mark)
            }
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in sink.yield(LinkPathMark(path)) }
        monitor.start(queue: DispatchQueue(label: "io.zephra.link.path"))
        self.monitor = monitor
    }

    /// Stops watching, which the app does the moment it goes to the background: a phone in a
    /// pocket is not about to act on a change of network.
    func stop() {
        monitor?.cancel()
        monitor = nil
        reports?.finish()
        reports = nil
        drain = nil
        mark = nil
        lastAction = nil
    }

    /// What to do about one path, and the doing of it.
    private func react(to mark: LinkPathMark) {
        let reaction = Self.reaction(
            from: self.mark, to: mark, isLive: client.connection.isLive, lastAction: lastAction)
        self.mark = mark
        guard reaction != .nothing else { return }
        lastAction = Date()
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

    /// What a path is worth doing about, given the one before it and when anything was last
    /// done.
    ///
    /// The first report is nothing to act on: the app has just come to the front and is already
    /// dialling, and a redial on top of that is the same attempt twice. A path that carries
    /// nothing is nothing to act on either — no road would open over it, and the wait that is
    /// running is the right thing to be doing. Neither is a report inside `coalesce` of the last
    /// one acted on, since a handover is several reports and one change. What is left is a path
    /// that is different and can carry something, and there the answer depends on whether there
    /// is a session: a live one may be a ghost, so it is asked; anything else is dialled at
    /// once, which covers the wait after a failure, a Mac that turned this phone away, and being
    /// plainly offline.
    static func reaction(
        from previous: LinkPathMark?, to current: LinkPathMark, isLive: Bool,
        lastAction: Date? = nil, now: Date = Date()
    ) -> LinkPathReaction {
        guard let previous, previous != current, current.isSatisfied else { return .nothing }
        if let lastAction, now.timeIntervalSince(lastAction) < coalesce.seconds { return .nothing }
        return isLive ? .probe : .redial
    }
}

extension Duration {
    /// This span in seconds, for comparing against the dates the system deals in.
    fileprivate var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
