import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraLinkClient

/// A whole file over a road that keeps losing frames, which is what the relay is under load.
///
/// A 6 MB picture is about ninety-six chunks and a 40 MB clip two and a half thousand. Asking for
/// the whole file again on every hole meant a large clip finished only by luck: each attempt got
/// as far as the next lost frame and then started over.
@MainActor
@Suite("A file the road interrupts is asked for from where it got to")
struct LinkBlobResumeTests {
    /// A phone past its handshake and past the library pull the first snapshot starts, holding a
    /// gap for milliseconds rather than half a second: a suite that counts frames until one is
    /// dropped has to know which frames those are.
    private static func connected(payload: Data) async throws -> LinkClientUnderTest {
        let bed = try await LinkGapRecoveryTests.connected()
        bed.host.payload = payload
        return bed
    }

    /// Four megabytes, which is sixty-four chunks: enough that a road losing one frame in fifty
    /// loses one of them.
    private static let file = Data((0..<(4 * 1024 * 1024)).map { UInt8($0 % 251) })

    @Test("only the tail crosses again after a hole, and the caller still gets the whole file")
    func onlyTheTailCrossesAgain() async throws {
        let bed = try await Self.connected(payload: Self.file)
        defer { Task { await bed.host.stop() } }
        bed.road.dropEvery(50)

        let bytes = try await bed.client.file(name: "a.mp4")

        #expect(bytes == Self.file, "the whole file is what the caller sees")
        #expect(bed.road.dropCount > 0, "the road has to have actually lost some")
        #expect(bed.host.sentFromChunk.count > 1, "so the file was asked for more than once")
        #expect(
            bed.host.sentFromChunk.first == 0,
            "the first ask is for the whole file, as it always was")
        #expect(
            bed.host.sentFromChunk.dropFirst().allSatisfy { $0 > 0 },
            "and every ask after it carries on from where the one before it stopped")
    }

    @Test("a Mac that ignores fromChunk still delivers the file")
    func anOlderMacStillDelivers() async throws {
        // `fromChunk` is omitted from the JSON at zero and decoded as zero when absent, so a Mac
        // built before this reads the command it always read and sends the whole file. The
        // phone's reassembly starts fresh on a chunk that arrives at index 0.
        let bed = try await Self.connected(payload: Self.file)
        defer { Task { await bed.host.stop() } }
        bed.host.ignoresFromChunk = true
        // One hole, part way in: what is being asked here is what the phone does with a whole
        // file it did not ask for, not how many holes it survives.
        bed.road.dropFrame(after: 20)

        let bytes = try await bed.client.file(name: "a.mp4")

        #expect(bytes == Self.file, "the whole file, from a Mac that never heard of a tail")
        #expect(bed.host.sentFromChunk.count > 1)
    }

    @Test("a thumbnail is asked for whole, since a tail of one chunk saves nothing")
    func aThumbnailDoesNotResume() async throws {
        let picture = Data((0..<200_000).map { UInt8($0 % 251) })
        let bed = try await Self.connected(payload: picture)
        defer { Task { await bed.host.stop() } }
        // The reply and the first chunk go past; the one behind them is lost, and the chunk after
        // that arriving out of turn is what says so.
        bed.road.dropFrame(after: 2)

        #expect(try await bed.client.thumbnail(name: "a.png", pixels: 256) == picture)
        #expect(
            bed.host.commands.filter { $0 == .fetchThumbnail(name: "a.png", pixels: 256) }.count
                == 2,
            "asked twice, and both times for the whole of it")
    }
}
