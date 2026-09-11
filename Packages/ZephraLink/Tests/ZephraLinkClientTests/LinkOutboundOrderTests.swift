import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol

/// What leaves the phone leaves in the order it was sealed in, whoever asked for it.
///
/// The Mac's channel requires the *exact* next counter, so a pair of frames that swap places is
/// not a slow reply — it is a session that cannot be opened again. Nothing here checks an order
/// directly: the real `SecureChannel` on the far end is the assertion.
@MainActor
@Suite("Two callers and a ping cannot reorder the phone's counter")
struct LinkOutboundOrderTests {
    @Test("two concurrent requests and an incoming ping leave the channel open")
    func concurrentRequestsKeepTheChannel() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.host.stop() } }
        await bed.client.connect()
        // One round trip first, so the Mac has read the confirm and has a channel of its own.
        try await bed.client.cancel()

        async let first: Void = bed.client.cancel()
        async let second: Void = bed.client.setFavourite(names: ["a.png"], on: true)
        // A ping the phone answers with a pong, sealed from the reader while both requests are
        // in flight: three frames, three counters, one stream.
        try await bed.host.announce(["ping": true], kind: .ping)
        _ = try await (first, second)

        #expect(bed.host.commands.count == 3)
        #expect(bed.client.connection == .live(.lan), "the far end could still open what arrived")
        // One more proves the counters are still in step after all of it.
        try await bed.client.cancel()
        #expect(bed.host.commands.count == 4)
    }

    @Test("a blob's chunks and a request beside them stay in the order they were sealed")
    func blobChunksKeepTheirPlace() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.host.stop() } }
        await bed.client.connect()
        let picture = Data((0..<200_000).map { UInt8($0 % 251) })

        async let queued: UUID = bed.client.enqueue(
            GenerationRequest(
                modelID: "z-image-turbo-4bit", count: 1, settings: ClientFixtures.settings),
            reference: picture)
        async let other: Void = bed.client.cancel()
        _ = try await (queued, other)

        #expect(bed.host.blobs == [picture])
        #expect(bed.client.connection == .live(.lan))
    }
}
