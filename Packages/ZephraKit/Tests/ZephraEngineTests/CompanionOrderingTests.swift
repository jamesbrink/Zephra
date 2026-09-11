import Foundation
import Testing
import ZephraCore
import ZephraLinkHost
import ZephraLinkProtocol

@testable import ZephraEngine

/// What the Mac does with a stream the relay reordered on the way in.
///
/// The relay is one Lambda invocation per frame and those invocations post concurrently, so a
/// picture's chunks and a run of requests arrive overtaken. The session reads through an
/// `OrderedInbox`, so everything above it — `BlobReassembly` above all, which takes chunks in
/// order only — sees the stream the phone actually sealed.
@MainActor
@Suite("A session reads a reordered stream in the order it was sent")
struct CompanionOrderingTests {
    @Test("a picture whose chunks arrived out of order is still the picture")
    func aReorderedPictureLands() async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        let picture = Data((0..<200_000).map { UInt8($0 % 251) })
        let start = BlobStart(byteCount: picture.count, mime: "image/png")
        try await phone.send(start, kind: .blobStart)
        let chunks = BlobChunker.chunks(of: picture, blobID: start.blobID).map(Frame.chunk)
        #expect(chunks.count >= 4, "a picture worth reordering is more than one chunk")
        try await phone.send(chunks, arrivingAs: Self.shuffled(chunks.count))

        var request = CompanionHostTests.request()
        request.referenceBlobID = start.blobID
        let reply = try await phone.request(.enqueue(request))

        guard case .queued = reply else {
            Issue.record("the picture did not arrive whole: \(reply)")
            return
        }
        await bed.shutdown()
    }

    @Test("requests that arrived out of order are answered in the order they were sent")
    func reorderedRequestsAreHandledInOrder() async throws {
        let bed = CompanionTestBed()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        let envelopes = try (0..<4).map { index in
            try Envelope.encoding(
                Command.libraryPage(offset: index, limit: 1), kind: .request)
        }
        try await phone.send(envelopes.map(Frame.envelope), arrivingAs: [1, 0, 3, 2])

        for envelope in envelopes {
            _ = try await phone.waitFor { [weak phone] in
                phone?.envelopes.first { $0.kind == .reply && $0.inReplyTo == envelope.id }
            }
        }
        #expect(bed.host.sessions.count == 1, "reordering is not a reason to drop a phone")
        await bed.shutdown()
    }

    @Test("a frame the phone sent twice is dropped and the session stands")
    func aDuplicateFrameIsDropped() async throws {
        let bed = CompanionTestBed()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        let ping = Frame.envelope(Envelope(kind: .ping, body: Data("{}".utf8)))
        try await phone.send([ping], arrivingAs: [0, 0])
        try await phone.send([ping], arrivingAs: [0])
        try await bed.waitUntil { phone.envelopes.filter { $0.kind == .pong }.count == 2 }

        #expect(bed.host.sessions.count == 1)
        await bed.shutdown()
    }

    /// An order with at least one pair swapped, for `count` frames.
    static func shuffled(_ count: Int) -> [Int] {
        var order = Array(0..<count)
        var index = 0
        while index + 1 < count {
            order.swapAt(index, index + 1)
            index += 2
        }
        return order
    }
}
