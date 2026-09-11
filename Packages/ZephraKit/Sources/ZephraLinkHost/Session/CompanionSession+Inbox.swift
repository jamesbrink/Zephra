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
        inbox.onLoss { [weak self] gap in
            Task { @MainActor in
                guard let session = self, !session.isClosed else { return }
                // At info and with the counters: a loss is rare, ends the session, and leaves
                // nothing else to look at afterwards. What went missing is the whole diagnosis.
                session.host?.logger.info(
                    "companion lost a frame from a phone (\(gap.summary, privacy: .public)); the session is finished")
                await session.close()
            }
        }
        return inbox
    }
}
