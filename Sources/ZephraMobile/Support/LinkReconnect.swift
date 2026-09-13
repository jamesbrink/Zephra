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
    ///
    /// Written by the waits in `LinkReconnect+Waiting` and by nothing outside this type.
    var nextAttemptAt: Date?

    @ObservationIgnored let client: LinkClient
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Whatever has to finish before a new loop may start: the loop `end()` cancelled and the
    /// disconnect behind it, or the loop `retryNow()` cancelled. Read once, by `begin()`, and
    /// handed to the loop it makes.
    @ObservationIgnored private var settling: Task<Void, Never>?
    @ObservationIgnored var attempt = 0
    /// The client's endings, iterated once and for the life of this object: an `AsyncStream`
    /// has one consumer, and an iterator that is dropped ends the stream behind it.
    @ObservationIgnored var endings: SessionEndings?

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
        // What to wait on is taken **here**, not read inside the loop. A loop that read the
        // property when it finally ran could find a wait that `end()` had installed in the
        // meantime — and that wait is `await theLoop.value` and a disconnect behind it, so the
        // loop would be waiting for the task that is waiting for the loop, and the session
        // would never be closed at all.
        let previous = settling
        task = Task { [weak self] in await self?.run(after: previous) }
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

    func stopAndDrain() async {
        end()
        await settling?.value
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
    ///
    /// - Parameter previous: whatever the loop this one replaces left behind, as of the moment
    ///   this loop was made: a cancelled loop being waited out, and the disconnect behind it
    ///   where `end()` was what took it down. An attempt already in flight is not something a
    ///   cancellation stops part way through, and a second loop over one would be two roads to
    ///   one Mac.
    private func run(after previous: Task<Void, Never>?) async {
        await previous?.value
        while !Task.isCancelled {
            // A phone with no Mac has nothing to dial, and the loop stops rather than spinning.
            // It takes itself down with it: a loop that has stopped while `task` still holds it
            // is an `isRunning` that lies and a `begin()` that does nothing for the rest of the
            // launch, so a phone that pairs in the same foreground it launched in would have no
            // reconnection at all. The composition root calls `begin()` again when a Mac is
            // paired, and this is what lets that mean something.
            guard client.pairedHost != nil else { return finished() }
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

    /// The loop stopping of its own accord. Nothing to do where somebody else has already taken
    /// it down, since `task` is then not this loop.
    private func finished() {
        guard !Task.isCancelled else { return }
        task = nil
        nextAttemptAt = nil
    }
}
