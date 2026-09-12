import Foundation
import ZephraLinkProtocol

/// Asking a session that looks live whether it is one.
extension LinkClient {
    /// How long the Mac has to answer a ping before the session is taken as gone.
    ///
    /// Short, because the whole point is to be quicker than a request that has to wait out
    /// `requestTimeout` before anybody learns anything, and long enough that a Mac in the middle
    /// of a step on the far side of a relay still answers inside it.
    public static let probeTimeout: Duration = .seconds(5)

    /// Asks the Mac to say something, and ends the session where it does not.
    ///
    /// A phone that has moved from Wi-Fi to cellular keeps the socket it had: the interface it
    /// was opened on is gone, nothing is delivered over it, and neither end is told. The session
    /// therefore looks live — the state says so, the library offers its edits — until somebody
    /// presses something and waits half a minute for a timeout. A ping costs one frame and
    /// settles it in five seconds, and every way it can fail is the same way: the session is
    /// over, which is what wakes the reconnection.
    ///
    /// The Mac has answered `ping` with a `pong` carrying `inReplyTo` since the first build, so
    /// this needs nothing new at that end. Nothing is asked of a road that has no channel on it
    /// yet, and nothing at all of a frozen client.
    ///
    /// - Parameter timeout: how long to wait, which only a suite passes.
    public func probe(timeout: Duration = LinkClient.probeTimeout) async {
        guard !isFrozen, let session, session.channel != nil else { return }
        let envelope = Envelope(kind: .ping, body: Data("{}".utf8))
        do {
            _ = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Reply, any Error>) in
                pending[envelope.id] = continuation
                timers[envelope.id] = expire(envelope.id, after: timeout)
                do { try send(.envelope(envelope)) } catch { fail(envelope.id, with: error) }
            }
        } catch {
            logger.notice("The Mac did not answer a probe; the session is finished.")
            await roadEnded(session, error: LinkClientError.timedOut)
        }
    }
}
