import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol

/// What a live session does with what the Mac sends, and what it sends back.
@MainActor
@Suite("A live session holds the Mac's state and answers for it")
struct LinkSessionTests {
    /// A paired phone with a session already open.
    private func live() async throws -> LinkClientUnderTest {
        let bed = LinkClientUnderTest()
        try await bed.client.pair(with: bed.pairingCode())
        try await settle()
        return bed
    }

    @Test("a snapshot arrives whole, and the deltas after it edit that state")
    func snapshotThenDeltas() async throws {
        let bed = try await live()
        defer { Task { await bed.host.stop() } }
        try await bed.host.announce(ClientFixtures.snapshot, kind: .snapshot)
        try await settle()
        #expect(bed.client.snapshot?.libraryCount == 3)
        try await bed.host.announce(StateDelta.acceptsWork(false), kind: .delta)
        try await bed.host.announce(
            StateDelta.engine(EngineStateDTO(kind: .generating, step: 2, steps: 9, isBusy: true)),
            kind: .delta)
        try await settle()
        #expect(bed.client.snapshot?.acceptsWork == false)
        #expect(bed.client.snapshot?.engine.step == 2)
    }

    @Test("a preview frame lands beside the state and goes when the run does")
    func previewArrivesAndClears() async throws {
        let bed = try await live()
        defer { Task { await bed.host.stop() } }
        try await bed.host.announce(ClientFixtures.snapshot, kind: .snapshot)
        try await bed.host.announce(
            PreviewFrameDTO(jpeg: Data([0xFF, 0xD8]), width: 256, height: 256, step: 3, steps: 9),
            kind: .preview)
        try await settle()
        #expect(bed.client.preview?.step == 3)
        try await bed.host.announce(
            StateDelta.engine(EngineStateDTO(kind: .ready)), kind: .delta)
        try await settle()
        #expect(bed.client.preview == nil)
    }

    @Test("the library is reset, added to and taken from")
    func libraryChanges() async throws {
        let bed = try await live()
        defer { Task { await bed.host.stop() } }
        let first = ClientFixtures.entry("one.png")
        let second = ClientFixtures.entry("two.png")
        bed.host.library = [first, second]
        try await bed.host.announce(
            StateDelta.library(.reset([first, second], total: 2)), kind: .delta)
        try await settle { bed.client.libraryIsComplete }
        #expect(bed.client.library.map(\.fileName) == ["one.png", "two.png"])
        bed.host.library = [ClientFixtures.entry("three.png"), first, second]
        try await bed.host.announce(
            StateDelta.library(.upserted([ClientFixtures.entry("three.png")])), kind: .delta)
        try await settle { bed.client.library.contains { $0.fileName == "three.png" } }
        #expect(bed.client.library.contains { $0.fileName == "three.png" })
        bed.host.library = [ClientFixtures.entry("three.png"), second]
        try await bed.host.announce(StateDelta.library(.removed(["one.png"])), kind: .delta)
        try await settle { bed.client.library.count == 2 && !bed.client.library.contains { $0.fileName == "one.png" } }
        #expect(Set(bed.client.library.map(\.fileName)) == ["three.png", "two.png"])
    }

    @Test("a command crosses and its reply closes it")
    func requestRoundTrip() async throws {
        let bed = try await live()
        defer { Task { await bed.host.stop() } }
        #expect(try await bed.client.request(.cancel) == .ok)
        #expect(bed.host.commands == [.cancel])
    }

    @Test("a refusal comes back as the Mac's own error, thrown")
    func refusalIsThrown() async throws {
        let bed = try await live()
        defer { Task { await bed.host.stop() } }
        bed.host.reply = .error(LinkError(code: .busy, reason: "The Mac is busy."))
        await #expect(throws: LinkError(code: .busy, reason: "The Mac is busy.")) {
            try await bed.client.switchModel("z-image-turbo-4bit")
        }
    }

    @Test("a blob fetch puts the chunks back together")
    func blobReassembles() async throws {
        let bed = try await live()
        defer { Task { await bed.host.stop() } }
        let bytes = Data((0..<200_000).map { UInt8($0 % 251) })
        bed.host.payload = bytes
        #expect(try await bed.client.thumbnail(name: "one.png", pixels: 512) == bytes)
    }

    @Test("a reference picture goes first, as a blob the request names")
    func enqueueSendsTheReferenceFirst() async throws {
        let bed = try await live()
        defer { Task { await bed.host.stop() } }
        let picture = Data(repeating: 0x42, count: 70_000)
        _ = try await bed.client.enqueue(
            GenerationRequest(
                modelID: ClientFixtures.model.id, count: 1, settings: ClientFixtures.settings),
            reference: picture)
        #expect(bed.host.blobs == [picture])
        guard case .enqueue(let request) = bed.host.commands.last else {
            return #expect(Bool(false), "the Mac was asked to generate")
        }
        #expect(request.referenceBlobID != nil)
    }

    @Test("a withdrawn pairing is forgotten the moment the Mac says so")
    func revokedForgetsTheHost() async throws {
        let bed = try await live()
        defer { Task { await bed.host.stop() } }
        try await bed.host.announce(
            LinkError(code: .revoked, reason: "This Mac no longer knows this device."),
            kind: .error)
        try await settle { bed.client.pairedHost == nil }
        #expect(bed.client.pairedHost == nil)
        #expect(try bed.store.loadPairedHost() == nil)
    }

    /// Lets the frames in flight land: everything here is one process and one actor, so a
    /// couple of turns of the loop is the whole of the wait.
    private func settle(_ until: @MainActor () -> Bool = { true }) async throws {
        for _ in 0..<8 { await Task.yield() }
        let deadline = ContinuousClock.now + .seconds(2)
        while !until(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(until())
    }
}
