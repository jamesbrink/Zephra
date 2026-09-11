import Foundation

/// One stream of whole frames to one peer, which is all the secure channel asks of a road.
///
/// A TCP connection on the local network and the relay's WebSocket both conform; the
/// channel seals a frame, hands the bytes here, and reads sealed bytes back, never knowing
/// which road carried them. Frames arrive whole: a road that is a byte stream underneath
/// (TCP) prefixes each frame with its length itself, and a road that is message-based (a
/// WebSocket) hands one message through as one frame.
public protocol LinkConnection: Sendable {
    /// Every frame the peer sends, in order, until the road closes. Read once; a second call
    /// is a programming error and may return an empty stream.
    func frames() -> AsyncThrowingStream<Data, Error>
    /// Hands one frame to the peer, whole.
    func send(_ frame: Data) async throws
    /// Closes the road; `frames()` finishes.
    func close() async
}

/// The Mac's side of a road: something that yields connections as peers arrive.
public protocol LinkListener: Sendable {
    /// Every peer that connects, until `stop()`.
    func connections() -> AsyncStream<any LinkConnection>
    func stop() async
}
