import Foundation
import Observation
import ZephraLinkClient
import ZephraLinkTransport

/// Keeping the phone connected to its Mac for as long as it is in front of somebody.
///
/// `LinkClient.connect()` is one attempt at every road, and it is idempotent; what is missing
/// from it is a policy, and a policy is the app's business rather than the client's. This is
/// the whole of it: try while the app is active, wait `LinkBackoff`'s one, two, four, eight
/// seconds after each failure, capped at thirty, and stop the moment the app goes to the
/// background — a phone in a pocket has no reason to hold a socket open, and the Mac has no
/// reason to hold a session for it.
///
/// Observable because the wait is on screen: `nextAttemptAt` is what the Settings row counts
/// down to and what its Retry Now button skips. The client carries the same moment on
/// `LinkConnectionState.waiting`, which is what every other surface reads; this is the policy's
/// own copy, and the one thing that can shorten it.
///
/// One task, because two would race to open two roads to the same Mac. `begin()` is safe to
/// call again: the loop that is already running is the one that keeps running, so a second
/// foreground does not restart the wait.
@MainActor
@Observable
final class LinkReconnect {
    /// How often a live session is looked at when there is nothing else to wake on.
    ///
    /// `LinkClient.sessionEndings()` is what the wait normally sits on, so a session that ends —
    /// a `peer left`, a send that failed, a socket that went — is reconnected at once rather
    /// than on the next beat. This is the fallback for a stream that has finished: one enum read
    /// on the main actor, and only while the app is in front and the session is up.
    static let heartbeat: Duration = .seconds(2)

    /// When the next attempt is due, or nil whenever nothing is being waited out.
    private(set) var nextAttemptAt: Date?

    @ObservationIgnored private let client: LinkClient
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Whatever has to finish before a new loop may start: the loop `end()` cancelled and the
    /// disconnect behind it, or the loop `retryNow()` cancelled. Awaited at the top of `run()`,
    /// because an attempt already in flight is not something a cancellation stops part way
    /// through, and a second loop over one is two roads to one Mac.
    @ObservationIgnored private var settling: Task<Void, Never>?
    @ObservationIgnored private var attempt = 0
    /// The client's endings, iterated once and for the life of this object: an `AsyncStream`
    /// has one consumer, and an iterator that is dropped ends the stream behind it.
    @ObservationIgnored private var endings: SessionEndings?

    /// Reconnection for one client.
    init(client: LinkClient) {
        self.client = client
    }

    /// Whether the loop is running, which is what "the app is in front" looks like from here.
    var isRunning: Bool { task != nil }

    /// The app came to the front: connect, and keep connecting.
    ///
    /// The count of failures resets here, because a person who has just opened the app is owed
    /// an immediate attempt rather than the tail of a wait that started while it was away.
    func begin() {
        guard task == nil else { return }
        attempt = 0
        task = Task { [weak self] in await self?.run() }
    }

    /// The app went to the background: stop trying, and let the session go.
    ///
    /// The loop is waited on before the session is closed. An attempt already in flight is not
    /// something a cancellation can be relied on to stop part way through, and closing under
    /// one would leave a road opening onto a client that thinks it is offline.
    func end() {
        guard let running = stopTheLoop() else { return }
        settling = Task { [client] in
            await running.value
            await client.disconnect()
        }
    }

    /// Dial now rather than at the end of the wait.
    ///
    /// What the Settings row's Retry Now does, and what a change of network path does: the wait
    /// was sized for a Mac that had not moved, and a phone that has just joined a network is
    /// owed the attempt it would otherwise sit out. Nothing while the app is away, since there
    /// is no loop to hurry along.
    func retryNow() {
        guard let running = stopTheLoop() else { return }
        settling = Task { await running.value }
        begin()
    }

    /// Takes the loop down and hands back what has to be waited on, or nil where there was none.
    private func stopTheLoop() -> Task<Void, Never>? {
        guard let running = task else { return nil }
        task = nil
        nextAttemptAt = nil
        running.cancel()
        return running
    }

    /// Try, wait, try again, until the app goes away.
    private func run() async {
        await settling?.value
        settling = nil
        while !Task.isCancelled {
            guard client.pairedHost != nil else { return }
            await client.connect()
            guard !Task.isCancelled else { return }
            if client.connection.isLive {
                attempt = 0
                await waitForTheSessionToEnd()
                continue
            }
            attempt += 1
            guard await waitBeforeTheNextAttempt() else { return }
        }
    }

    /// The wait between two attempts, said out loud.
    ///
    /// The moment is written to the client and to `nextAttemptAt` before the sleep rather than
    /// after it, so nothing on screen shows a bare failure through a wait that is already
    /// running. A cancellation is the answer to `end()` and to `retryNow()` alike: the loop
    /// stops, and whichever of the two cancelled it decides what happens next.
    private func waitBeforeTheNextAttempt() async -> Bool {
        let delay = LinkBackoff.delay(after: attempt)
        let due = Date().addingTimeInterval(Double(delay.components.seconds))
        nextAttemptAt = due
        client.markWaiting(until: due)
        do { try await Task.sleep(for: delay) } catch { return false }
        nextAttemptAt = nil
        return true
    }

    /// Sits on a live session until it is not one, so the next turn of the loop reconnects.
    ///
    /// The client says so itself. Only where that stream has finished does this fall back to
    /// asking every couple of seconds, since a wait on a finished stream would spin.
    private func waitForTheSessionToEnd() async {
        let endings = endings ?? SessionEndings(client.sessionEndings())
        self.endings = endings
        while !Task.isCancelled, client.connection.isLive {
            if await endings.next() == nil {
                do { try await Task.sleep(for: Self.heartbeat) } catch { return }
            }
        }
    }
}

/// One iterator over a client's endings, off the main actor, so waiting on it is not a mutation
/// of actor-isolated state — and kept, since an `AsyncStream` iterator that is dropped ends the
/// stream behind it. Single consumer by construction: `LinkReconnect` is the only thing that
/// waits on one.
private nonisolated final class SessionEndings: @unchecked Sendable {
    private var iterator: AsyncStream<Void>.AsyncIterator

    init(_ stream: AsyncStream<Void>) { iterator = stream.makeAsyncIterator() }

    /// The next ending, or nil once there will be no more.
    func next() async -> Void? { await iterator.next() }
}
