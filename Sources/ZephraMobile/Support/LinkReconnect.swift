import Foundation
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
/// One task, because two would race to open two roads to the same Mac. `begin()` is safe to
/// call again: the loop that is already running is the one that keeps running, so a second
/// foreground does not restart the wait.
@MainActor
final class LinkReconnect {
    /// How often a live session is looked at to see whether it is still live.
    ///
    /// `connection` is observable, but the sequence that would wake a task on a change of it is
    /// iOS 26, and the phone runs on 18. So the loop asks, cheaply and rarely: this is one
    /// enum read on the main actor, and only while the app is in front and the session is up.
    static let heartbeat: Duration = .seconds(2)

    private let client: LinkClient
    private var task: Task<Void, Never>?
    private var attempt = 0

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
        let running = task
        task = nil
        running?.cancel()
        Task { [client] in
            await running?.value
            await client.disconnect()
        }
    }

    /// Try, wait, try again, until the app goes away.
    private func run() async {
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
            do { try await Task.sleep(for: LinkBackoff.delay(after: attempt)) } catch { return }
        }
    }

    /// Sits on a live session until it is not one, so the next turn of the loop reconnects.
    private func waitForTheSessionToEnd() async {
        while !Task.isCancelled, client.connection.isLive {
            do { try await Task.sleep(for: Self.heartbeat) } catch { return }
        }
    }
}
