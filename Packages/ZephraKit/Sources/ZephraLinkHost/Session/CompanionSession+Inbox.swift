import Foundation
import ZephraLinkProtocol

/// Where the order a phone sealed its frames in is put back, and what happens when one of them
/// never arrives.
///
/// The relay is one Lambda invocation per frame and they post here concurrently, so a phone
/// sending a picture's chunks or a run of requests has them arrive overtaken. Everything above
/// this reads one ordered stream, `BlobReassembly` most of all, so the session reads through an
/// `OrderedInbox` and never touches the channel's receiving half itself.
extension CompanionSession {
    /// The inbox this session reads through, with the answer to a gap it could not fill.
    ///
    /// A gap is no longer the end of the session. The frames the phone sent are the only copy, so
    /// what the hole swallowed is gone — but only that: a lost request is one the phone asks for
    /// again, and a lost chunk costs the transfer it was in and nothing else. Closing the session
    /// over one dropped frame meant a phone reconnecting every few seconds for the length of a
    /// run, which is worse than the hole.
    func makeInbox(over channel: SecureChannel) -> OrderedInbox {
        let inbox = OrderedInbox(channel: channel, hold: host?.frameHold ?? connection.frameReorderingHold)
        inbox.onGap { [weak self] gap, frames in
            Task { @MainActor in
                guard let session = self, !session.isClosed else { return }
                await session.stepOver(gap, releasing: frames)
            }
        }
        return inbox
    }

    /// A hole in what the phone said, stepped over.
    ///
    /// At error and with the counters: a skip is rare, costs the phone a whole `resync`, and is
    /// the first thing to look for when a session behaves oddly. The transfer that was arriving
    /// goes with it — its chunks are an ordered run and one of them is missing — so the request
    /// that names the picture is refused as `notFound` rather than assembled out of a hole.
    func stepOver(_ gap: FrameGap, releasing frames: [Frame]) async {
        host?.logger.error(
            """
            companion stepped over a gap in a phone's stream (\(gap.summary, privacy: .public)); \
            the session carries on
            """)
        incoming = nil
        incomingID = nil
        for frame in frames { await receiveAfterGap(frame) }
    }

    /// One frame the skip released, handled as if it had just arrived — and refused rather than
    /// fatal where it cannot be: a chunk of the transfer the hole was in the middle of is the
    /// ordinary case, and the phone is told so.
    private func receiveAfterGap(_ frame: Frame) async {
        do {
            try await receive(frame)
        } catch let error as LinkError {
            try? sendError(error)
        } catch {
            host?.logger.error(
                "companion could not read a frame after a gap: \(String(describing: error), privacy: .public)")
        }
    }
}
