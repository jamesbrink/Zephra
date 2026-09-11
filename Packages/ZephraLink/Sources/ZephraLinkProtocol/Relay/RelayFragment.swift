import Foundation

/// Cutting one payload into pieces a WebSocket frame can carry.
///
/// API Gateway advertises 128 KB, but that is the limit on a *message*: one frame may carry at
/// most 32 KB, and `URLSessionWebSocketTask` sends a message as a single frame. A 64 KiB blob
/// chunk sealed and base64'd is about 87 KB, so the relay closed the socket on the first one
/// — `NSPOSIXErrorDomain 57`, with nothing said about why.
///
/// So the client fragments, not the relay. A slice is 18,000 bytes, which is exactly 24,000
/// characters of base64 and a multiple of three: concatenating the slices' bytes and
/// concatenating their base64 are the same answer, which is the rule the relay's README states.
/// The three fields ride as ordinary extra fields on a `send`, which the relay forwards verbatim.
public enum RelayFragment {
    /// The most base64 one `d` may carry, which is what the relay's README fixes.
    public static let base64Limit = 24_000
    /// The bytes that make exactly that much base64. A multiple of three, so no slice pads.
    public static let byteLimit = base64Limit / 4 * 3
    /// The most slices one payload may be cut into, which bounds what a receiver will hold for
    /// one message id: a megabyte and a half, where the largest frame this build sends is 64 KiB
    /// sealed.
    public static let sliceLimit = 88
    /// How many hex characters a message id is.
    public static let idLength = 16

    /// A fresh message id: eight random bytes as sixteen lowercase hex characters.
    public static func newID() -> String {
        RandomBytes.make(idLength / 2).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether a payload has to be cut at all.
    public static func needsFragmenting(_ payload: Data) -> Bool { payload.count > byteLimit }

    /// One payload as the messages to send: a single unfragmented `send` when it fits, and a run
    /// of slices sharing one message id when it does not.
    public static func messages(for payload: Data, id: String = newID()) -> [RelayMessage] {
        guard needsFragmenting(payload) else { return [.send(payload: payload)] }
        let slices = stride(from: 0, to: payload.count, by: byteLimit).map { start in
            payload[payload.startIndex + start..<payload.index(
                payload.startIndex, offsetBy: min(start + byteLimit, payload.count))]
        }
        return slices.enumerated().map { index, slice in
            .send(payload: Data(slice), message: id, index: index, count: slices.count)
        }
    }
}
