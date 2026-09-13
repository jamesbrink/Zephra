import Foundation
import ZephraLinkClient
import ZephraLinkTransport

/// The two things the loop waits on: the wait between attempts, and a session that is live.
///
/// A file of their own because the loop above is a policy — when to try, when to stop, when to
/// hurry — and these are how a wait is actually taken, which is a different question.
extension LinkReconnect {
    /// The wait between two attempts, said out loud.
    ///
    /// The moment is written to the client and to `nextAttemptAt` before the sleep rather than
    /// after it, so nothing on screen shows a bare failure through a wait that is already
    /// running. A cancellation is the answer to `end()` and to `retryNow()` alike: the loop
    /// stops, and whichever of the two cancelled it decides what happens next.
    func waitBeforeTheNextAttempt() async -> Bool {
        let delay = LinkBackoff.delay(after: attempt) + .milliseconds(Int.random(in: 0...350))
        let due = Date().addingTimeInterval(Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18)
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
    func waitForTheSessionToEnd() async {
        let endings = endings ?? SessionEndings(client.sessionEndings())
        self.endings = endings
        while !Task.isCancelled, client.connection.isLive {
            if await endings.next() == nil {
                do { try await Task.sleep(for: Self.heartbeat) } catch { return }
            }
        }
    }
}
