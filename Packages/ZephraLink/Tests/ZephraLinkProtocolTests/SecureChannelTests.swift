import CryptoKit
import Foundation
import Testing
@testable import ZephraLinkProtocol

@Suite("The sealed channel refuses anything it did not expect")
struct SecureChannelTests {
    /// Two channels over one pair of keys, facing each other.
    static func channels() -> (SecureChannel, SecureChannel) {
        let one = SymmetricKey(size: .bits256)
        let other = SymmetricKey(size: .bits256)
        return (
            SecureChannel(sendKey: one, receiveKey: other),
            SecureChannel(sendKey: other, receiveKey: one)
        )
    }

    static let ping = Frame.envelope(Envelope(kind: .ping, body: Data("{}".utf8)))

    @Test("Frames in order open, one after another")
    func framesInOrderOpen() throws {
        let (sender, receiver) = Self.channels()
        for _ in 0..<5 {
            #expect(try receiver.open(try sender.seal(Self.ping)) == Self.ping)
        }
        #expect(!receiver.isClosed)
    }

    @Test("A gap in the stream closes the channel for good")
    func gapClosesTheChannel() throws {
        let (sender, receiver) = Self.channels()
        _ = try sender.seal(Self.ping)
        let second = try sender.seal(Self.ping)
        #expect(throws: SecureChannelError.undecipherable) { try receiver.open(second) }
        #expect(receiver.isClosed)
        #expect(throws: SecureChannelError.closed) { try receiver.open(second) }
    }

    @Test("A changed byte closes the channel")
    func tamperingClosesTheChannel() throws {
        let (sender, receiver) = Self.channels()
        var sealed = try sender.seal(Self.ping)
        sealed[sealed.count - 1] ^= 0x01
        #expect(throws: SecureChannelError.undecipherable) { try receiver.open(sealed) }
        #expect(receiver.isClosed)
    }

    @Test("A frame relabelled as the other kind will not open")
    func kindIsAuthenticated() throws {
        let (sender, receiver) = Self.channels()
        var sealed = try sender.seal(Self.ping)
        sealed[0] = FrameCodec.chunkKind
        #expect(throws: SecureChannelError.undecipherable) { try receiver.open(sealed) }
    }

    @Test("A frame too short to hold a tag will not open")
    func shortFrameIsRefused() throws {
        let (_, receiver) = Self.channels()
        #expect(throws: SecureChannelError.undecipherable) {
            try receiver.open(Data([FrameCodec.envelopeKind]))
        }
    }

    @Test("A closed channel seals nothing more either")
    func closedChannelSealsNothing() throws {
        let (sender, _) = Self.channels()
        sender.close()
        #expect(throws: SecureChannelError.closed) { try sender.seal(Self.ping) }
    }

    @Test("The nonce is four zero bytes and the counter, big-endian")
    func nonceCountsUp() throws {
        let nonce = try SecureChannel.nonce(0x0102_0304_0506_0708)
        #expect(
            Data(nonce) == Data([0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8]))
    }

    @Test("A blob's chunks go through the channel unchanged")
    func chunksSurviveTheChannel() throws {
        let (sender, receiver) = Self.channels()
        let blob = Data((0..<150_000).map { UInt8($0 % 253) })
        let chunks = BlobChunker.chunks(of: blob)
        var reassembly = BlobReassembly(blobID: chunks[0].blobID)
        var finished: Data?
        for chunk in chunks {
            guard case .chunk(let read) = try receiver.open(try sender.seal(.chunk(chunk))) else {
                Issue.record("a chunk came back as something else")
                return
            }
            finished = try reassembly.accept(read)
        }
        #expect(finished == blob)
    }
}
