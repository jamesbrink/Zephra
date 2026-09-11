import Foundation
import Testing
@testable import ZephraLinkProtocol

@Suite("A blob is cut into chunks and put back together")
struct BlobTransferTests {
    @Test(
        "Every size is cut into the right number of chunks",
        arguments: [(0, 1), (1, 1), (65_536, 1), (65_537, 2), (131_072, 2), (131_073, 3)]
    )
    func sizesCutIntoChunks(byteCount: Int, expected: Int) {
        let chunks = BlobChunker.chunks(of: Data(count: byteCount))
        #expect(chunks.count == expected)
        #expect(chunks.last?.isLast == true)
        #expect(chunks.map(\.bytes.count).reduce(0, +) == byteCount)
    }

    @Test("The chunks of a blob reassemble into the blob")
    func chunksReassemble() throws {
        let blob = Data((0..<200_000).map { UInt8($0 % 251) })
        let chunks = BlobChunker.chunks(of: blob)
        var reassembly = BlobReassembly(blobID: chunks[0].blobID, byteCount: blob.count)
        var finished: Data?
        for chunk in chunks { finished = try reassembly.accept(chunk) }
        #expect(finished == blob)
    }

    @Test("A chunk out of order is refused")
    func outOfOrderIsRefused() throws {
        let chunks = BlobChunker.chunks(of: Data(count: 200_000))
        var reassembly = BlobReassembly(blobID: chunks[0].blobID, byteCount: 200_000)
        _ = try reassembly.accept(chunks[0])
        #expect(throws: LinkError.self) { try reassembly.accept(chunks[2]) }
    }

    @Test("A chunk sent twice is refused")
    func duplicateIsRefused() throws {
        let chunks = BlobChunker.chunks(of: Data(count: 200_000))
        var reassembly = BlobReassembly(blobID: chunks[0].blobID, byteCount: 200_000)
        _ = try reassembly.accept(chunks[0])
        #expect(throws: LinkError.self) { try reassembly.accept(chunks[0]) }
    }

    @Test("A chunk belonging to another blob is refused")
    func foreignChunkIsRefused() {
        let chunks = BlobChunker.chunks(of: Data(count: 10))
        var reassembly = BlobReassembly(blobID: UUID(), byteCount: 10)
        #expect(throws: LinkError.self) { try reassembly.accept(chunks[0]) }
    }

    @Test("A blob past the cap is refused rather than held")
    func capIsEnforced() throws {
        let big = BlobReassembly.byteCap / BlobChunker.chunkSize + 1
        var reassembly = BlobReassembly(
            blobID: UUID(), byteCount: big * BlobChunker.chunkSize)
        let id = reassembly.blobID
        for index in 0..<UInt32(big) {
            let chunk = BlobChunk(
                blobID: id, index: index, count: UInt32(big) + 1,
                bytes: Data(count: BlobChunker.chunkSize))
            if index == UInt32(big) - 1 {
                #expect(throws: LinkError.self) { try reassembly.accept(chunk) }
            } else {
                _ = try reassembly.accept(chunk)
            }
        }
    }

    @Test("An empty blob is one empty chunk that completes")
    func emptyBlobCompletes() throws {
        let chunks = BlobChunker.chunks(of: Data())
        var reassembly = BlobReassembly(blobID: chunks[0].blobID, byteCount: 0)
        #expect(try reassembly.accept(chunks[0]) == Data())
    }

    @Test("A blob longer than it announced is refused on the chunk that passes the claim")
    func aLongerBlobThanAnnouncedIsRefused() throws {
        // The announcement is what the far end accepted the transfer on, so the sender is held
        // to it: without this a thumbnail could arrive as sixty-four megabytes.
        let blob = Data(count: 200_000)
        let chunks = BlobChunker.chunks(of: blob)
        var reassembly = BlobReassembly(blobID: chunks[0].blobID, byteCount: 70_000)
        _ = try reassembly.accept(chunks[0])
        #expect(throws: LinkError.self) { try reassembly.accept(chunks[1]) }
    }

    @Test("A blob shorter than it announced is refused rather than handed back short")
    func aShorterBlobThanAnnouncedIsRefused() throws {
        let chunks = BlobChunker.chunks(of: Data(count: 100))
        var reassembly = BlobReassembly(blobID: chunks[0].blobID, byteCount: 200)
        #expect(throws: LinkError.self) { try reassembly.accept(chunks[0]) }
    }

    @Test("A claim past the cap is trimmed to it, not taken at its word")
    func aClaimPastTheCapIsTrimmed() {
        #expect(
            BlobReassembly(blobID: UUID(), byteCount: BlobReassembly.byteCap * 4).byteCount
                == BlobReassembly.byteCap)
        #expect(BlobReassembly(blobID: UUID(), byteCount: -1).byteCount == 0)
    }
}
