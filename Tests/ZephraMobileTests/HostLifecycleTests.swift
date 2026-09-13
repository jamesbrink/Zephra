import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol
@testable import ZephraMobile

@MainActor @Suite("Independent mobile host lifecycles")
struct HostLifecycleTests {
    @Test func disablingForgettingAndForeground() async throws {
        let phone = DeviceIdentity()
        let a = MobileHostFixture(name: "A", phone: phone), b = MobileHostFixture(name: "B", phone: phone)
        let disk = MemoryHostPersistence()
        let persistence = try PairedHosts(keychain: disk)
        let catalog = LibraryCatalog(libraryRoot: nil, filesRoot: nil)
        let connections = HostConnections(storage: persistence, catalog: catalog,
            makeClient: { _ in MobilePreview.unpairedClient() })
        for fixture in [a, b] {
            try persistence.set(fixture.preference)
            connections.add(fixture.preference, client: fixture.client)
        }
        let observing = Task { await connections.observe() }
        connections.setActive(true)
        try await MobileHostFixture.settle { a.client.supportsMultiHost && b.client.supportsMultiHost }
        let bSession = try #require(b.client.authenticatedSessionID)
        var disabled = a.preference
        disabled.enabled = false
        connections.update(disabled)
        try await MobileHostFixture.settle { !a.client.connection.isLive }
        #expect(b.client.authenticatedSessionID == bSession)
        try await b.client.setTags(names: ["b.png"], tags: ["while-a-disabled"])
        #expect(b.host.commands.contains(.setTags(names: ["b.png"], tags: ["while-a-disabled"])))
        #expect(!a.host.commands.contains(.setTags(names: ["b.png"], tags: ["while-a-disabled"])))
        connections.setActive(false)
        for host in connections.hosts { await host.reconnect?.stopAndDrain() }
        #expect(!b.client.connection.isLive)
        connections.setActive(true)
        try await MobileHostFixture.settle { b.client.supportsMultiHost }
        #expect(b.client.authenticatedSessionID != bSession)
        #expect(!a.client.connection.isLive)
        let removed = try #require(connections.hosts.first { $0.id == a.preference.id })
        await connections.forget(removed)
        #expect(persistence.all().map(\.id) == [b.preference.id])
        #expect(connections.hosts.map(\.id) == [b.preference.id])
        try await b.client.setFavourite(names: ["b.png"], on: true)
        #expect(b.host.commands.contains(.setFavourite(names: ["b.png"], on: true)))
        observing.cancel()
        connections.setActive(false)
        for host in connections.hosts { await host.reconnect?.stopAndDrain() }
        await observing.value
        await a.stop(); await b.stop()
    }
    @Test func revocationAndPairingRepair() async throws {
        let a = MobileHostFixture(name: "A"), b = MobileHostFixture(name: "B")
        let connections = HostConnections(storage: nil,
            catalog: LibraryCatalog(libraryRoot: nil, filesRoot: nil), makeClient: { _ in a.client })
        connections.add(a.preference, client: a.client)
        connections.add(b.preference, client: b.client)
        let observing = Task { await connections.observe() }
        defer { observing.cancel(); connections.setActive(false) }
        connections.setActive(true)
        try await MobileHostFixture.settle { a.client.supportsMultiHost && b.client.supportsMultiHost }
        let otherSession = b.client.authenticatedSessionID
        try await a.host.announce(LinkError(code: .revoked, reason: "Pairing revoked"), kind: .error)
        try await MobileHostFixture.settle { connections.hosts.count == 1 }
        #expect(connections.hosts.first?.id == b.preference.id)
        #expect(b.client.authenticatedSessionID == otherSession)
        let code = PairingPayload(hostName: "A", keys: a.host.publicKeys,
            endpoints: a.preference.host.endpoints, secret: Data(repeating: 9, count: PairingSecret.byteCount),
            expiresAt: Date().addingTimeInterval(60))
        try await connections.pair(code)
        try await MobileHostFixture.settle { a.client.supportsMultiHost }
        #expect(connections.hosts.count == 2)
        #expect(Set(connections.hosts.map(\.id)).count == 2)
        #expect(b.client.authenticatedSessionID == otherSession)
        try await b.client.setTags(names: ["still-b.png"], tags: ["usable"])
        observing.cancel(); connections.setActive(false)
        for host in connections.hosts { await host.reconnect?.stopAndDrain() }
        await observing.value
        await a.stop(); await b.stop()
    }

}
