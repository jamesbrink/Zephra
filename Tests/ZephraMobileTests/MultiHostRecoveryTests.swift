import Foundation
import Testing
import ZephraCore
import ZephraLinkClient
import ZephraLinkProtocol
@testable import ZephraMobile

@MainActor @Suite("Multi-host recovery preserves library revisions and reference ownership")
struct MultiHostRecoveryTests {
    @Test func listingReconnect() async throws {
        let a = MobileHostFixture(name: "A")
        a.host.library = (0..<250).map { LibraryFixtures.cached("old-\($0).png").entry }
        let (gate, release) = AsyncStream<Void>.makeStream()
        a.host.beforeReply = { command in
            if case .multiHost(.listing(let offset, _, _)) = command, offset == 100 { for await _ in gate {} }
        }
        await a.client.connect()
        try await MobileHostFixture.settle { a.host.commands.contains {
            if case .multiHost(.listing(let offset, _, _)) = $0 { return offset == 100 }; return false
        } }
        #expect(!a.client.libraryIsComplete)
        await a.client.disconnect()
        release.finish(); a.host.beforeReply = nil
        a.host.library = (0..<250).map { LibraryFixtures.cached("new-\($0).png").entry }
        await a.client.connect()
        try await MobileHostFixture.settle { a.client.libraryIsComplete }
        #expect(a.client.library == a.host.library)
        await a.stop()
    }

    @Test func adoptedReferenceCrossesAnotherSessionAgain() async throws {
        let a = MobileHostFixture(name: "A"), b = MobileHostFixture(name: "B")
        let catalog = LibraryCatalog(libraryRoot: nil, filesRoot: nil)
        for fixture in [a, b] {
            fixture.host.library = [LibraryFixtures.cached("same.png").entry]
            _ = catalog.addHost(fixture.preference.id, client: fixture.client, frozen: false)
            await fixture.client.connect()
        }
        a.host.payload = ReferenceIntentTests.Bed.picture(width: 64, height: 32)
        b.host.payload = ReferenceIntentTests.Bed.picture(width: 32, height: 64)
        try await MobileHostFixture.settle { catalog.entries.count == 2 && b.client.supportsMultiHost }
        let source = try #require(catalog.entries.first { $0.hostID == a.preference.id })
        let intent = ReferenceIntent(), draft = PromptDraft()
        intent.use(source.id)
        await ReferenceAdoption.take(intent, from: catalog) { picture, origin in
            draft.adopt(picture, origin: origin, fitting: ReferenceIntentTests.Bed.pictureCapabilities.capabilities)
            return true
        }
        #expect(intent.canGenerate)
        let bytes = try #require(draft.reference)
        let input = GenerationInput(data: bytes, originHost: source.hostID, dimensions: draft.referenceSize)
        let job = StrictGeneration(request: GenerationRequest(modelID: "qwen-image-4bit", count: 1,
            settings: draft.settings), input: input)
        let receipt = GenerationReceipt(requestID: job.request.requestID, digest: try job.digest(),
            batchID: UUID(), status: .accepted)
        b.host.onCommand = { command in
            if case .multiHost(.submit) = command { b.host.reply = .multiHost(.receipt(receipt)) }
            else { b.host.reply = nil }
        }
        let first = try await b.client.submit(job, reference: bytes)
        await b.client.disconnect()
        await b.client.connect()
        try await MobileHostFixture.settle { b.client.supportsMultiHost }
        let second = try await b.client.submit(job, reference: bytes)
        #expect(first.batchID == second.batchID)
        #expect(b.host.blobs == [bytes, bytes])
        #expect(a.host.blobs.isEmpty)
        let submitted = b.host.commands.compactMap { command -> StrictGeneration? in
            if case .multiHost(.submit(let generation)) = command { return generation }; return nil
        }
        #expect(submitted.count == 2)
        #expect(submitted[0].request.referenceBlobID != submitted[1].request.referenceBlobID)
        #expect(submitted.allSatisfy { $0.input?.originHost == source.hostID && $0.input?.matches(bytes) == true })
        await a.stop(); await b.stop()
        await catalog.removeHost(a.preference.id); await catalog.removeHost(b.preference.id)
    }

    @Test func repeatedPressesBeforeSnapshotSendNothing() async throws {
        let a = MobileHostFixture(name: "A")
        a.host.publishesSnapshotOnConnect = false
        let hosts = HostConnections(storage: nil,
            catalog: LibraryCatalog(libraryRoot: nil, filesRoot: nil), makeClient: { _ in a.client })
        hosts.add(a.preference, client: a.client)
        let dispatch = GenerationDispatch(hosts: hosts, root: nil)
        dispatch.destination = a.preference.id
        await a.client.connect()
        let job = StrictGeneration(request: GenerationRequest(modelID: "z-image-turbo-4bit", count: 1,
            settings: PromptDraft().settings))
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 { group.addTask { await dispatch.send(job, reference: nil) } }
        }
        #expect(dispatch.submissions.isEmpty)
        #expect(!a.host.commands.contains { if case .enqueue = $0 { return true }; if case .multiHost(.submit) = $0 { return true }; return false })
        await a.stop(); await hosts.catalog.removeHost(a.preference.id)
    }
}
