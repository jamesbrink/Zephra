import Foundation
import Testing
import ZephraLinkProtocol
@testable import ZephraMobile

@MainActor
@Suite("Upscaling uses the picture's owning Mac")
struct LibraryUpscaleTests {
    @Test func routesFactorsAndRefusals() async throws {
        let catalog = LibraryCatalog(libraryRoot: nil, filesRoot: nil)
        let a = MobileHostFixture(name: "A"), b = MobileHostFixture(name: "B")
        for fixture in [a, b] {
            fixture.host.library = [LibraryFixtures.entry("same.png")]
            _ = catalog.addHost(fixture.preference.id, client: fixture.client, frozen: false)
            await fixture.client.connect()
        }
        defer { Task { await a.stop(); await b.stop() } }
        try await MobileHostFixture.settle { catalog.entries.count == 2 }
        let entry = try #require(catalog.entries.first { $0.hostID == b.preference.id })
        for factor in [2, 4] {
            try await catalog.upscale(entry, factor: factor)
            #expect(b.host.commands.contains(.upscale(name: "same.png", factor: factor)))
            #expect(!a.host.commands.contains(.upscale(name: "same.png", factor: factor)))
        }
        b.host.reply = .error(LinkError(code: .busy, reason: "The Mac is busy."))
        do {
            try await catalog.upscale(entry, factor: 2)
            Issue.record("A refusal must reach the interface")
        } catch let error as LinkError {
            #expect(error.reason == "The Mac is busy.")
        }
        await b.client.disconnect()
        await #expect(throws: LibraryCacheError.self) {
            try await catalog.upscale(entry, factor: 2)
        }
    }

    @Test func rejectsVideoAndUnknownOwner() async throws {
        let catalog = LibraryCatalog(libraryRoot: nil, filesRoot: nil)
        await #expect(throws: LinkError.self) {
            try await catalog.upscale(CachedEntry(LibraryFixtures.clip), factor: 2)
        }
        await #expect(throws: LinkError.self) {
            try await catalog.upscale(CachedEntry(LibraryFixtures.template), factor: 3)
        }
        let host = MobileHostFixture(name: "Forgotten Mac")
        let entry = CachedEntry(LibraryFixtures.template, hostID: host.preference.id)
        await #expect(throws: LibraryCacheError.self) {
            try await catalog.upscale(entry, factor: 2)
        }
    }
}
