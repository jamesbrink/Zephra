import Foundation
import ZephraLinkProtocol

/// What a road writes into the relay, and how fast.
extension RelayConnection {
    /// How many messages a second one road writes into the relay.
    ///
    /// The account's throttle is 500 requests a second shared by every invocation, and both
    /// directions of a session go through it. A run publishes about thirty messages a second of
    /// deltas and previews, so 120 leaves the interactive traffic four times the room it needs
    /// while a transfer is going. At this rate a 6 MB picture's ~580 slices cross in 3.2 seconds
    /// and a 40 MB clip's ~4,000 in 21, which is slower than the socket would take them and
    /// faster than a picture that fails at chunk 630 and starts again.
    public static let messagesPerSecond = 120

    /// How many messages may go at once before the pacing bites. A thumbnail is two or three
    /// slices and a reply is one, so a burst of 40 leaves everything interactive unpaced in
    /// practice and only a transfer ever meets the cadence.
    public static let burst = 40

    /// One sealed frame to the other end, cut into slices where it is too big for one frame.
    ///
    /// API Gateway allows a 128 KB *message* but a 32 KB *frame*, and `URLSessionWebSocketTask`
    /// sends a message as one frame: a 64 KiB blob chunk sealed and base64'd is about 87 KB, and
    /// the relay closed the socket on the first one with nothing said about why. So a large
    /// payload goes as `RelayFragment` slices, which the far end puts back together.
    ///
    /// Each slice waits its turn at the road's own `RelayCadence` first. Written back to back, a
    /// picture's hundreds of slices and a clip's thousands arrive at the account's shared
    /// 500-a-second throttle as one burst, and a throttle answers a burst by refusing the tail of
    /// it — which is a frame the far end never sees, a hole in its counters, and the whole
    /// transfer. The ping, the allow-list and the join do not come through here and are not
    /// paced: they are one message each and none of them is ever the burst.
    ///
    /// A write that fails takes the road down with it. The socket is dead either way, and a road
    /// that stays open over a dead socket is a session the Mac keeps and the phone cannot reach:
    /// the failure finishes `frames()`, which is what everything above reads the end of a
    /// session from.
    public func send(_ frame: Data) async throws {
        guard lock.withLock({ state.isJoined && !state.isClosed }) else { throw RelayError.closed }
        do {
            for message in RelayFragment.messages(for: frame) {
                await cadence.wait()
                try await write(message)
            }
        } catch {
            logger.error(
                """
                The relay socket refused a frame of \(frame.count, privacy: .public) bytes: \
                \(String(describing: error), privacy: .public)
                """)
            fail(error)
            throw error
        }
    }
}
