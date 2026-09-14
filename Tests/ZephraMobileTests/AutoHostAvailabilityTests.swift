import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol
@testable import ZephraMobile

@MainActor @Suite("Auto remains available when another Mac goes away")
struct AutoHostAvailabilityTests {
    @Test func disconnectedRecommendationImmediatelyFallsBack() async throws {
        let a = MobileHostFixture(name: "Watched Mac"), b = MobileHostFixture(name: "Available Mac")
        let hosts = connections(a, b)
        for fixture in [a, b] { await fixture.client.connect() }
        try await MobileHostFixture.settle { a.client.supportsMultiHost && b.client.supportsMultiHost }
        let dispatch = GenerationDispatch(hosts: hosts, root: nil)
        dispatch.offers = [a.preference.id: offer(seconds: 10), b.preference.id: offer(seconds: 60)]
        dispatch.received = [a.preference.id: .now, b.preference.id: .now]
        dispatch.recommended = a.preference.id
        #expect(dispatch.target?.id == a.preference.id)

        await a.client.disconnect()
        #expect(hosts.visible?.id == a.preference.id)
        #expect(dispatch.target?.id == b.preference.id)
        #expect(!dispatch.reason.contains("Reconnect"))

        dispatch.destination = a.preference.id
        #expect(dispatch.target?.id == a.preference.id)
        #expect(dispatch.reason.contains("Reconnect"))
        await a.stop(); await b.stop()
        for fixture in [a, b] { await hosts.catalog.removeHost(fixture.preference.id) }
    }

    @Test func healthyOfferPublishesBeforeSilentHostTimesOut() async throws {
        let a = MobileHostFixture(name: "Silent Mac"), b = MobileHostFixture(name: "Available Mac")
        let hosts = connections(a, b)
        a.host.silentOffers = true
        b.host.reply = .multiHost(.offer(offer(seconds: 60)))
        for fixture in [a, b] { await fixture.client.connect() }
        try await MobileHostFixture.settle { a.client.supportsMultiHost && b.client.supportsMultiHost }
        let dispatch = GenerationDispatch(hosts: hosts, root: nil)
        let generation = StrictGeneration(request: GenerationRequest(
            modelID: "z-image-turbo-4bit", count: 1, settings: PromptDraft().settings))
        var completed = false
        let refresh = Task {
            await dispatch.refresh(generation)
            completed = true
        }
        try await MobileHostFixture.settle { dispatch.target?.id == b.preference.id }
        #expect(!completed, "The healthy Mac should be usable before the silent offer times out")
        await refresh.value
        #expect(dispatch.target?.id == b.preference.id)
        await a.stop(); await b.stop()
        for fixture in [a, b] { await hosts.catalog.removeHost(fixture.preference.id) }
    }

    private func connections(_ a: MobileHostFixture, _ b: MobileHostFixture) -> HostConnections {
        let hosts = HostConnections(storage: nil,
            catalog: LibraryCatalog(libraryRoot: nil, filesRoot: nil), makeClient: { _ in a.client })
        for fixture in [a, b] { hosts.add(fixture.preference, client: fixture.client) }
        return hosts
    }

    private func offer(seconds: Double) -> HostOffer {
        HostOffer(refusal: nil, queueSeconds: 0, preparationSeconds: 0,
            executionSeconds: seconds, memoryMargin: 1000, modelLoaded: true,
            queueCount: 0, queueRevision: "test", physicalMemory: 10000)
    }
}
