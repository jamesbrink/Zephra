import Foundation
import ZephraLinkProtocol

/// What the phone does about a frame that never arrived.
///
/// A gap used to be the end of the session: the phone reconnected, and over a run that lost a
/// frame every few seconds it reconnected until it gave up. A hole costs one message, so the
/// phone steps over it, costs the one transfer or request the hole was in the middle of, and
/// asks the Mac for the world again.
extension LinkClient {
    /// The inbox this session reads through, with the answer to a gap it could not fill.
    func inbox(over channel: SecureChannel, for session: LinkSession) -> OrderedInbox {
        let inbox = OrderedInbox(channel: channel, hold: frameHold ?? session.road.frameReorderingHold)
        inbox.onGap { [weak self, weak session] gap, frames in
            Task { @MainActor in
                guard let self, let session else { return }
                await self.lost(session, gap: gap, releasing: frames)
            }
        }
        return inbox
    }

    /// A gap the Mac's stream never filled, stepped over.
    ///
    /// At error and with the counters: a skip is rare, costs a whole resync, and is the first
    /// thing to look for when the phone behaves oddly. The state the lost deltas were editing is
    /// asked for whole rather than patched around, and the frames the skip released are
    /// dispatched behind that, as if they had just arrived.
    ///
    /// **A hole costs the one thing it swallowed.** This used to fail every open request and drop
    /// every transfer in flight, on the reasoning that the hole might have been any of them. Over
    /// the relay it is not: a picture is hundreds of chunks and a clip thousands, so a hole
    /// arrives in the middle of a transfer that is *still going*, and throwing away the other
    /// three transfers and the library page in flight turned one lost message into five. What the
    /// hole actually swallowed says so itself: a transfer whose next chunk is out of turn fails
    /// as `lost` in `receive`, and a request whose reply never comes has `requestTimeout`, which
    /// is this end's own promise and was always the thing that closed it.
    func lost(_ session: LinkSession, gap: FrameGap, releasing frames: [Frame]) async {
        logger.error(
            "A frame never arrived (\(gap.summary, privacy: .public)); asking the Mac for the world again."
        )
        resync()
        for frame in frames { dispatch(frame) }
    }

    /// Asks the Mac for the whole of its state again. Answered `.ok` and then a fresh snapshot,
    /// which is what puts the phone back in step — the library pull included, since it restarts
    /// on a snapshot landing.
    private func resync() {
        do {
            try send(.envelope(try Envelope.encoding(Command.resync, kind: .request)))
        } catch {
            logger.error(
                "The resync did not go out: \(String(describing: error), privacy: .public)")
        }
    }
}
