import Foundation
import ZephraLinkProtocol

/// What the phone does about a frame that never arrived.
///
/// A gap used to be the end of the session: the phone reconnected, and over a run that lost a
/// frame every few seconds it reconnected until it gave up. A hole costs one message, so the
/// phone steps over it, throws away everything the missing frame might have been part of, and
/// asks the Mac for the world again.
extension LinkClient {
    /// The inbox this session reads through, with the answer to a gap it could not fill.
    func inbox(over channel: SecureChannel, for session: LinkSession) -> OrderedInbox {
        let inbox = OrderedInbox(channel: channel, hold: frameHold)
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
    /// thing to look for when the phone behaves oddly. What the hole may have swallowed is a
    /// blob's chunk and a reply, so every transfer in flight is dropped and every request still
    /// open is failed as `lost` — both of which the caller asks again once — and then the state
    /// the deltas were editing is asked for whole rather than patched around. The frames the
    /// skip released are dispatched behind that, as if they had just arrived.
    func lost(_ session: LinkSession, gap: FrameGap, releasing frames: [Frame]) async {
        logger.error(
            "A frame never arrived (\(gap.summary, privacy: .public)); asking the Mac for the world again."
        )
        settleEverything(with: LinkClientError.lost)
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
