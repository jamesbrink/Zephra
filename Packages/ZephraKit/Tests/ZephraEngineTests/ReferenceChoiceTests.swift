import Foundation
import Testing
import ZephraCore
@testable import ZephraEngine

@Suite("Choosing a reference picture")
@MainActor
struct ReferenceChoiceTests {
    @Test("a slow picture chosen first does not land after a quick one chosen second")
    func theLatestChoiceWins() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        try #require(store.descriptor.capabilities.supportsReferenceImage)
        let slow = Data([1]), quick = Data([2])

        let release = AsyncStream<Void>.makeStream()
        store.adoptReference {
            for await _ in release.stream {}
            return slow
        }
        let earlier = store.referenceRead
        store.adoptReference { quick }
        await store.referenceRead?.value
        release.continuation.finish()
        await earlier?.value

        #expect(store.settings.referenceImage == quick)
    }

    @Test("a choice made now cancels the read still in flight")
    func aNewChoiceCancelsTheRead() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        try #require(store.descriptor.capabilities.supportsReferenceImage)

        let release = AsyncStream<Void>.makeStream()
        store.adoptReference {
            for await _ in release.stream {}
            return Data([1])
        }
        let earlier = store.referenceRead
        let ticket = store.claimReference()
        store.useAsReference(nil, ticket: ticket)
        release.continuation.finish()
        await earlier?.value

        #expect(store.settings.referenceImage == nil)
        #expect(store.referenceChoice == ticket, "the slow read took no number of its own after")
    }

    @Test("Generate waits for the picture on its way into the well")
    func generationWaitsForTheRead() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        try #require(store.canGenerate)

        store.adoptReference { Data([1]) }
        #expect(store.isAdoptingReference)
        #expect(!store.canGenerate)
        #expect(!store.canQueue)
        await store.referenceRead?.value

        #expect(!store.isAdoptingReference)
        #expect(store.canGenerate)
        #expect(store.settings.referenceImage == Data([1]))
    }

    @Test("a stale ticket lands nothing")
    func aStaleTicketIsIgnored() async {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        let first = store.claimReference()
        _ = store.claimReference()

        store.useAsReference(Data([1]), ticket: first)

        #expect(store.settings.referenceImage == nil)
    }
}
