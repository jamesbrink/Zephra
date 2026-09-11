import Foundation
import Network
import ZephraLinkProtocol

/// Turning the byte stream back into frames, which is the half of a TCP road that has rules.
extension TCPConnection {
    /// Reads one length, then one body of that length, then asks for the next.
    ///
    /// A loop written as a chain of callbacks rather than as `for await`: `NWConnection` hands
    /// bytes back on its own queue, and re-entering here from the completion keeps exactly one
    /// read outstanding at a time, which is what makes the frames arrive in order.
    func readNextFrame() {
        receive(exactly: Self.prefixByteCount) { [weak self] header in
            guard let self else { return }
            let length = Int(header.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) })
            guard length <= Self.maxFrameBytes else {
                self.frameContinuation.finish(throwing: TCPConnectionError.frameTooLarge)
                self.connection.cancel()
                return
            }
            guard length > 0 else {
                self.frameContinuation.yield(Data())
                self.readNextFrame()
                return
            }
            self.receive(exactly: length) { body in
                self.frameContinuation.yield(body)
                self.readNextFrame()
            }
        }
    }

    /// Exactly `count` bytes, or the end of the stream.
    ///
    /// `minimumIncompleteLength` and `maximumLength` are both `count`, so Network does the
    /// gathering: a frame split across packets arrives here whole, and a short read means the
    /// peer went away part way through one.
    private func receive(exactly count: Int, then body: @escaping @Sendable (Data) -> Void) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                if !self.isClosed { self.frameContinuation.finish(throwing: error) }
                return
            }
            guard let data, data.count == count else {
                if isComplete || data == nil { self.frameContinuation.finish() }
                return
            }
            body(data)
        }
    }
}
