import CryptoKit
import Foundation
import Synchronization

/// The sealed pipe both ends talk through once the handshake is done.
///
/// AES-GCM under two keys, one per direction, with the nonce counted rather than random: a
/// counter cannot repeat by accident, and requiring the *exact* next one on the way in is what
/// makes a replayed or dropped frame a failure instead of something the receiver quietly
/// accepts. The frame's kind byte is the authenticated context, so a chunk cannot be replayed
/// as an envelope.
///
/// One failure closes the channel for good. There is nothing to recover to: a frame that did
/// not authenticate means the stream is not the one that started, and carrying on would let an
/// attacker probe until something got through.
public final class SecureChannel: Sendable {
    /// How many frames one direction may carry before the nonce space runs out.
    public static let counterLimit: UInt64 = 1 << 32

    private struct State {
        var sendCounter: UInt64 = 0
        var receiveCounter: UInt64 = 0
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

    /// One frame as the bytes to send: the kind byte, then the sealed body and its tag.
    public func seal(_ frame: Frame) throws -> Data {
        let counter = try take(\.sendCounter)
        do {
            let kind = frame.kind
            let box = try AES.GCM.seal(
                try FrameCodec.body(of: frame), using: sendKey,
                nonce: Self.nonce(counter), authenticating: Data([kind]))
            return Data([kind]) + box.ciphertext + box.tag
        } catch {
            close()
            throw error
        }
    }

    /// The frame those bytes are, or a failure that closes the channel.
    public func open(_ data: Data) throws -> Frame {
        let counter = try take(\.receiveCounter)
        do {
            return try Self.unseal(data, key: receiveKey, counter: counter)
        } catch {
            close()
            throw error
        }
    }

    /// The next counter for one direction, closing the channel where there is none left.
    private func take(_ path: WritableKeyPath<State, UInt64>) throws -> UInt64 {
        try state.withLock { state in
            guard !state.isClosed else { throw SecureChannelError.closed }
            guard state[keyPath: path] < Self.counterLimit else {
                state.isClosed = true
                throw SecureChannelError.rekeyRequired
            }
            defer { state[keyPath: path] += 1 }
            return state[keyPath: path]
        }
    }

    /// Four zero bytes and the counter, big-endian: twelve bytes, never repeated under one key.
    static func nonce(_ counter: UInt64) throws -> AES.GCM.Nonce {
        var bytes = Data(count: 4)
        withUnsafeBytes(of: counter.bigEndian) { bytes.append(contentsOf: $0) }
        return try AES.GCM.Nonce(data: bytes)
    }
}
