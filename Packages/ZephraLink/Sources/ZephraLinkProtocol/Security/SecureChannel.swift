import CryptoKit
import Foundation
import Synchronization

/// The sealed pipe both ends talk through once the handshake is done.
///
/// AES-GCM under two keys, one per direction, with the nonce counted rather than random: a
/// counter cannot repeat by accident. The counter is **sent**, in the clear, ahead of the
/// ciphertext, because a frame's place in the stream is not its place on the wire. Every `send`
/// through the relay is a Lambda invocation of its own and those invocations reach the far end
/// concurrently, so a sustained stream of deltas arrives out of order; an implicit counter turned
/// the first overtaken frame into a frame that would not open.
///
/// The counter is not in the additional authenticated data, and does not need to be: it **is**
/// the nonce. A changed counter is a different nonce, the tag does not verify, and the frame is
/// `undecipherable`. The AAD stays the frame's kind byte, so a chunk cannot be replayed as an
/// envelope. A sealed frame on the wire is `kind || counter (8, big-endian) || ciphertext || tag`.
///
/// What the channel refuses is anything outside a window over the stream: a counter at or below
/// the last one released downstream is `replayed`, and one a whole `receiveWindow` beyond it is
/// `outOfWindow`. Neither closes the channel — reordering is ordinary and a duplicate is cheap to
/// drop. Only a frame that does not authenticate closes it, for good: that means the stream is
/// not the one that started, and carrying on would let an attacker probe until something got
/// through.
///
/// Putting the opened frames back in order is `OrderedInbox`'s job, and it is what moves the
/// release point on with `released(through:)`.
public final class SecureChannel: Sendable {
    /// How many frames one direction may carry before the nonce space runs out.
    public static let counterLimit: UInt64 = 1 << 32
    /// How far past the release point a frame may sit and still be opened. Wide enough that a
    /// relay's concurrent invocations cannot exhaust it, narrow enough that a counter plucked out
    /// of the air is refused rather than decrypted against.
    public static let receiveWindow: UInt64 = 1024
    /// The bytes the counter occupies, between the kind byte and the ciphertext.
    public static let counterByteCount = 8

    private struct State {
        var sendCounter: UInt64 = 0
        /// The counter the next frame released downstream will carry. Everything below it has
        /// been handed on already.
        var receiveFloor: UInt64 = 0
        var isClosed = false
    }

    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private let state = Mutex(State())

    /// Creates a channel over one handshake's keys, from one end's point of view.
    public init(sendKey: SymmetricKey, receiveKey: SymmetricKey) {
        self.sendKey = sendKey
        self.receiveKey = receiveKey
    }

    /// Whether the channel has failed and stopped.
    public var isClosed: Bool { state.withLock(\.isClosed) }

    /// Closes the channel, so nothing more is sealed or opened.
    public func close() { state.withLock { $0.isClosed = true } }

    /// One frame as the bytes to send: the kind byte, the counter, then the sealed body and tag.
    public func seal(_ frame: Frame) throws -> Data {
        let counter = try takeSendCounter()
        do {
            let kind = frame.kind
            let box = try AES.GCM.seal(
                try FrameCodec.body(of: frame), using: sendKey,
                nonce: Self.nonce(counter), authenticating: Data([kind]))
            return Data([kind]) + Self.counterBytes(counter) + box.ciphertext + box.tag
        } catch {
            close()
            throw error
        }
    }

    /// The frame those bytes are and where in the stream it sat, or a failure.
    ///
    /// Only `undecipherable` and `rekeyRequired` close the channel. A frame outside the window is
    /// refused and nothing more: a relay that overtook one frame has not broken the stream.
    public func open(_ data: Data) throws -> OpenedFrame {
        let counter = try Self.counter(in: data)
        try admit(counter)
        do {
            return OpenedFrame(counter: counter, frame: try Self.unseal(data, key: receiveKey))
        } catch {
            close()
            throw error
        }
    }

    /// Records that every frame through `counter` has been handed on, which is what the window
    /// and the replay check are measured from. `OrderedInbox` calls it as it releases.
    public func released(through counter: UInt64) {
        state.withLock { state in
            guard counter >= state.receiveFloor else { return }
            state.receiveFloor = counter + 1
        }
    }

    /// The next counter to seal under, closing the channel where there is none left.
    private func takeSendCounter() throws -> UInt64 {
        try state.withLock { state in
            guard !state.isClosed else { throw SecureChannelError.closed }
            guard state.sendCounter < Self.counterLimit else {
                state.isClosed = true
                throw SecureChannelError.rekeyRequired
            }
            defer { state.sendCounter += 1 }
            return state.sendCounter
        }
    }

    /// Whether a frame at `counter` is one this channel will still open.
    private func admit(_ counter: UInt64) throws {
        try state.withLock { state in
            guard !state.isClosed else { throw SecureChannelError.closed }
            guard counter >= state.receiveFloor else { throw SecureChannelError.replayed }
            guard counter < state.receiveFloor + Self.receiveWindow else {
                throw SecureChannelError.outOfWindow
            }
            guard counter < Self.counterLimit else {
                state.isClosed = true
                throw SecureChannelError.rekeyRequired
            }
        }
    }

    /// Four zero bytes and the counter, big-endian: twelve bytes, never repeated under one key.
    static func nonce(_ counter: UInt64) throws -> AES.GCM.Nonce {
        try AES.GCM.Nonce(data: Data(count: 4) + counterBytes(counter))
    }

    /// The counter as the eight bytes that ride on the wire.
    static func counterBytes(_ counter: UInt64) -> Data {
        withUnsafeBytes(of: counter.bigEndian) { Data($0) }
    }
}
