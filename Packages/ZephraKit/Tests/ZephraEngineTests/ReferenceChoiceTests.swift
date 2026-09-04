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

        store.adoptReference { Thread.sleep(forTimeInterval: 0.2); return slow }
        store.adoptReference { quick }
        try await Task.sleep(for: .milliseconds(400))

        #expect(store.settings.referenceImage == quick)
    }

    @Test("a choice made now cancels the read still in flight")
    func aNewChoiceCancelsTheRead() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        try #require(store.descriptor.capabilities.supportsReferenceImage)

        store.adoptReference { Thread.sleep(forTimeInterval: 0.2); return Data([1]) }
        let ticket = store.claimReference()
        store.useAsReference(nil, ticket: ticket)
        try await Task.sleep(for: .milliseconds(400))

        #expect(store.settings.referenceImage == nil)
        #expect(store.referenceChoice == ticket, "the slow read took no number of its own after")
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
