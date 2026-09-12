import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol

@testable import ZephraLinkClient

/// What the phone will take bytes for, which is what a Mac can make it hold.
@MainActor
@Suite("The phone assembles only the blobs the Mac announced")
struct LinkBlobAdmissionTests {
    /// A phone with a live session to a Mac that answers with `payload`.
    private func connected(payload: Data? = nil) async -> LinkClientUnderTest {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        bed.host.payload = payload
        await bed.client.connect()
        return bed
    }

    @Test("a chunk for a blob nothing announced is dropped rather than assembled")
    func anUnannouncedChunkIsDropped() async throws {
        let bed = await connected()
        defer { Task { await bed.host.stop() } }
        let stray = BlobChunker.chunks(of: Data(count: 64), blobID: UUID())[0]

        bed.client.receive(stray)
        #expect(bed.client.blobs.isEmpty, "nothing is held for a transfer nobody announced")
        #expect(bed.client.connection == .live(.lan), "and the session carries on")
    }

    @Test("an announced blob is assembled and handed to whoever asked for it")
    func anAnnouncedBlobArrives() async throws {
        let picture = Data((0..<200_000).map { UInt8($0 % 251) })
        let bed = await connected(payload: picture)
        defer { Task { await bed.host.stop() } }

        #expect(try await bed.client.thumbnail(name: "a.png", pixels: 256) == picture)
        #expect(bed.client.blobs.isEmpty, "and nothing is left part way through")
        #expect(bed.client.blobOrder.isEmpty)
    }

    @Test("no more than four blobs are part way through, and the oldest is the one dropped")
    func theOldestTransferIsDropped() async throws {
        let bed = await connected()
        defer { Task { await bed.host.stop() } }
        let starts = (0..<LinkClient.blobLimit + 1).map { _ in
            BlobStart(byteCount: 200_000, mime: "image/png")
        }

        for start in starts { bed.client.announce(start) }
        #expect(bed.client.blobs.count == LinkClient.blobLimit)
        #expect(bed.client.blobs[starts[0].blobID] == nil, "the first announced fell off")
        #expect(bed.client.blobOrder == starts.dropFirst().map(\.blobID))
    }

    @Test("a file part way through is not evicted by thumbnails announced after it")
    func aWantedTransferSurvivesTheLimit() async throws {
        // The grid announcing five thumbnails used to evict the forty-megabyte clip somebody was
        // waiting on: the limit is there to bound what a Mac can make this phone hold unasked,
        // and a transfer the phone asked for is not that.
        let bed = await connected()
        defer { Task { await bed.host.stop() } }
        let file = BlobStart(byteCount: 40_000_000, mime: "video/mp4")

        bed.client.announce(file, wanted: true)
        for _ in 0..<(LinkClient.blobLimit + 2) {
            bed.client.announce(BlobStart(byteCount: 40_000, mime: "image/jpeg"))
        }

        #expect(bed.client.blobs[file.blobID] != nil, "the clip is still being assembled")
        #expect(!bed.client.blobOrder.contains(file.blobID), "and it is in nobody's count")
        #expect(bed.client.blobOrder.count == LinkClient.blobLimit)
    }

    @Test("a blob that never finishes is given up on rather than held for the session")
    func anUnfinishedTransferIsGivenUpOn() async throws {
        let bed = await connected()
        defer { Task { await bed.host.stop() } }
        let start = BlobStart(byteCount: 200_000, mime: "image/png")

        bed.client.announce(start)
        bed.client.receive(BlobChunker.chunks(of: Data(count: 200_000), blobID: start.blobID)[0])
        #expect(bed.client.blobs.count == 1, "part of it is held while it is still arriving")
        // A clock is started at the announcement rather than at the first `await` for it, which
        // is what a transfer nobody ever asked about needs.
        #expect(bed.client.timers[start.blobID] != nil)

        // What that clock does when it runs out, without waiting the two minutes for it.
        bed.client.fail(start.blobID, with: LinkClientError.timedOut)
        #expect(bed.client.blobs.isEmpty)
        #expect(bed.client.blobOrder.isEmpty)
        #expect(bed.client.timers[start.blobID] == nil)
    }

    @Test("a transfer's clock is idle time, re-armed by every chunk that lands")
    func theClockIsIdleTime() async throws {
        let bed = await connected()
        defer { Task { await bed.host.stop() } }
        let start = BlobStart(byteCount: 200_000, mime: "image/png")
        let chunks = BlobChunker.chunks(of: Data(count: 200_000), blobID: start.blobID)

        bed.client.announce(start, wanted: true)
        let announced = bed.client.timers[start.blobID]
        bed.client.receive(chunks[0])

        #expect(announced?.isCancelled == true, "the clock the announcement started is off")
        #expect(bed.client.timers[start.blobID] != nil, "and the chunk bought a fresh one")
        #expect(LinkClient.blobIdleTimeout == .seconds(15))
        #expect(LinkClient.blobLimit == 4)
    }
}
