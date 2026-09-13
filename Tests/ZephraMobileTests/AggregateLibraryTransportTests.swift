import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol
@testable import ZephraMobile

@MainActor @Suite("Aggregate library operations keep their encrypted host owner")
struct AggregateLibraryTransportTests {
    @Test func ownershipRollbackAndLateForget() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = LibraryCatalog(libraryRoot: directory.appending(path: "Library"), filesRoot: directory.appending(path: "Files"))
        let a = MobileHostFixture(name: "A"), b = MobileHostFixture(name: "B")
        let initial = LibraryFixtures.cached("same.png").entry
        for fixture in [a, b] {
            fixture.host.library = [initial]
            _ = catalog.addHost(fixture.preference.id, client: fixture.client, frozen: false)
            await fixture.client.connect()
        }
        defer { Task {
            a.host.beforeReply = nil; b.host.beforeReply = nil
            await a.stop(); await b.stop()
            await catalog.removeHost(a.preference.id); await catalog.removeHost(b.preference.id)
        } }
        try await MobileHostFixture.settle { catalog.entries.count == 2 && a.client.libraryIsComplete && b.client.libraryIsComplete }
        let left = try #require(catalog.entries.first { $0.hostID == a.preference.id })
        let right = try #require(catalog.entries.first { $0.hostID == b.preference.id })
        #expect(await catalog.setTags([left.id], tags: ["only-a"]))
        #expect(a.host.commands.contains(.setTags(names: ["same.png"], tags: ["only-a"])))
        #expect(!b.host.commands.contains(.setTags(names: ["same.png"], tags: ["only-a"])))
        #expect(catalog.entry(named: right.id)?.tags.contains("only-a") == false)
        var changed = initial
        changed.annotation.tags = ["newer-server-edit"]
        changed.version = "newer"
        changed.contentModifiedAt = Date().addingTimeInterval(1)
        let newer = changed
        a.host.beforeReply = { command in
            guard case .setTags = command else { return }
            a.host.library = [newer]
            try await a.host.announce(StateDelta.library(.upserted([newer])), kind: .delta)
            try await MobileHostFixture.settle { catalog.entry(named: left.id)?.tags == ["newer-server-edit"] }
            a.host.reply = .error(LinkError(code: .refused, reason: "Edit refused"))
        }
        #expect(!(await catalog.setTags([left.id], tags: ["failed-edit"])))
        #expect(catalog.entry(named: left.id)?.tags == ["newer-server-edit"])
        a.host.beforeReply = nil; a.host.reply = nil
        let (gate, release) = AsyncStream<Void>.makeStream()
        defer { release.finish() }
        a.host.payload = Data([1]); b.host.payload = Data([2])
        a.host.beforeReply = { command in
            if case .fetchFile = command { for await _ in gate {} }
        }
        let read = Task { await catalog.picture(named: left.id) }
        try await MobileHostFixture.settle { a.host.commands.contains { if case .fetchFile = $0 { return true }; return false } }
        let removing = Task { await catalog.removeHost(a.preference.id) }
        try await MobileHostFixture.settle { catalog.children[a.preference.id] == nil }
        #expect(await catalog.picture(named: right.id) == Data([2]))
        release.finish()
        #expect(await read.value == nil)
        await removing.value
        #expect(catalog.entry(named: left.id) == nil)
        #expect(await catalog.picture(named: right.id) == Data([2]))
        let removedEntries = EntryStore(root: directory.appending(path: "Library/Hosts/" + a.preference.id.rawValue))
        #expect(await removedEntries.load().isEmpty)
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: directory.appending(path: "Files").path)
        #expect(!remainingFiles.contains { $0.hasPrefix(a.preference.id.rawValue) })
    }
}
