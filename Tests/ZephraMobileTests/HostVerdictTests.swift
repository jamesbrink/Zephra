import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol
@testable import ZephraMobile

@MainActor @Suite("Generate follows the desktop verdict")
struct HostVerdictTests {
    @Test func explicitDestinationHonorsRefusalAndRecovery() async throws {
        let fixture = MobileHostFixture(name: "Desktop")
        let hosts = HostConnections(storage: nil,
            catalog: LibraryCatalog(libraryRoot: nil, filesRoot: nil), makeClient: { _ in fixture.client })
        hosts.add(fixture.preference, client: fixture.client)
        await fixture.client.connect()
        try await MobileHostFixture.settle { fixture.client.supportsMultiHost }
        let dispatch = GenerationDispatch(hosts: hosts, root: nil)
        dispatch.destination = fixture.preference.id
        var offer = HostOffer(refusal: "Desktop memory refusal", queueSeconds: nil,
            preparationSeconds: nil, executionSeconds: nil, memoryMargin: 1000,
            modelLoaded: true, queueCount: 0, queueRevision: "test", physicalMemory: 10000)
        dispatch.offers[fixture.preference.id] = offer
        dispatch.offerSessions[fixture.preference.id] = try #require(fixture.client.authenticatedSessionID)
        dispatch.received[fixture.preference.id] = .now
        #expect(!dispatch.canSend)
        #expect(dispatch.reason == "Desktop memory refusal")
        dispatch.destination = nil
        #expect(!dispatch.canSend)
        #expect(dispatch.reason == "Desktop: Desktop memory refusal")
        dispatch.destination = fixture.preference.id
        offer.refusal = nil
        dispatch.offers[fixture.preference.id] = offer
        #expect(dispatch.canSend)
        dispatch.received[fixture.preference.id] = .now - .seconds(6)
        #expect(!dispatch.canSend)
        await fixture.client.disconnect()
        #expect(!dispatch.canSend)
        await fixture.stop()
        await hosts.catalog.removeHost(fixture.preference.id)
    }
}
