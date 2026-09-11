import Foundation
import ZephraLinkProtocol

/// Where the order a phone sealed its frames in is put back.
///
/// The relay is one Lambda invocation per frame and they post here concurrently, so a phone
/// sending a picture's chunks or a run of requests has them arrive overtaken. Everything above
/// this reads one ordered stream, `BlobReassembly` most of all, so the session reads through an
/// `OrderedInbox` and never touches the channel's receiving half itself.
extension CompanionSession {
    /// The inbox this session reads through, with the answer to a gap it could not fill.
    ///
    /// Loss is the end of the session and nothing less: the frames the phone sent are the only
    /// copy, so a stream with a hole in it cannot be brought back. The phone reconnects, and a
    /// new channel opens on a snapshot of everything, which is the recovery.
    func makeInbox(over channel: SecureChannel) -> OrderedInbox {
        let inbox = OrderedInbox(channel: channel, hold: host?.frameHold ?? OrderedInbox.hold)
        inbox.onLoss { [weak self] in
            Task { @MainActor in
                guard let session = self, !session.isClosed else { return }
                session.host?.logger.notice(
                    "companion closed a session that lost a frame on the way in")
                await session.close()
            }
        }
        return inbox
    }
}
