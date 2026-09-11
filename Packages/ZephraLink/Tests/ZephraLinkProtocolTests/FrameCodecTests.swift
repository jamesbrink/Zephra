import Foundation
import Testing
@testable import ZephraLinkProtocol

@Suite("A frame survives being written and read back")
struct FrameCodecTests {
    @Test("An envelope keeps its id, kind, reply and body")
    func envelopeRoundTrips() throws {
        let request = UUID()
        let envelope = try Envelope.encoding(
            Command.cancel, kind: .request, inReplyTo: request)
        let decoded = try FrameCodec.decode(try FrameCodec.encode(.envelope(envelope)))
        guard case .envelope(let read) = decoded else {
            Issue.record("that frame read back as something else")
            return
        }
        #expect(read == envelope)
        #expect(read.inReplyTo == request)
        #expect(try read.decode(Command.self) == .cancel)
    }

    @Test("A chunk keeps its blob, its place and its bytes")
    func chunkRoundTrips() throws {
        let chunk = BlobChunk(
            blobID: UUID(), index: 3, count: 9, bytes: Data(repeating: 0xAB, count: 1000))
        let decoded = try FrameCodec.decode(try FrameCodec.encode(.chunk(chunk)))
        #expect(decoded == .chunk(chunk))
    }

    @Test("The leading byte says which kind a frame is")
    func kindLeadsTheFrame() throws {
        let envelope = try FrameCodec.encode(
            .envelope(Envelope(kind: .ping, body: Data("{}".utf8))))
        let chunk = try FrameCodec.encode(
            .chunk(BlobChunk(blobID: UUID(), index: 0, count: 1, bytes: Data())))
        #expect(envelope.first == FrameCodec.envelopeKind)
        #expect(chunk.first == FrameCodec.chunkKind)
    }

    @Test("An empty frame and an unknown kind are both refused")
    func brokenFramesAreRefused() {
        #expect(throws: LinkError.self) { try FrameCodec.decode(Data()) }
        #expect(throws: LinkError.self) { try FrameCodec.decode(Data([0x7F, 0x00])) }
    }

    @Test("A chunk shorter than its header is refused")
    func truncatedChunkIsRefused() {
        #expect(throws: LinkError.self) {
            try FrameCodec.decode(Data([FrameCodec.chunkKind]) + Data(count: 10))
        }
    }
}
