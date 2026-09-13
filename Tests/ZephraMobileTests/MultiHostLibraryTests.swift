import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol
@testable import ZephraMobile

@MainActor
@Suite("A combined library preserves host ownership")
struct MultiHostLibraryTests {
    @Test("One, two, four and eight hosts keep duplicate names distinct and sort deterministically", arguments: [1, 2, 4, 8])
    func combined(_ count: Int) async throws {
        let root = LibraryCatalog(libraryRoot: nil, filesRoot: nil)
        var ids: [HostID] = []
        for _ in 0..<count {
            let id = HostID(keys: DeviceIdentity().publicKeys)
            ids.append(id)
            let child = root.addHost(id, client: MobilePreview.unpairedClient(), frozen: true)
            child.stop()
            child.publish([LibraryFixtures.cached("same.png")])
        }
        #expect(root.entries.count == count)
        #expect(Set(root.entries.map(\.id)).count == count)
        for entry in root.entries {
            #expect(root.owner(of: entry)?.hostID == entry.hostID)
            #expect(root.entry(named: entry.id) == entry)
            let restored = try LinkJSON.decode(CachedEntry.self, from: LinkJSON.encode(entry))
            #expect(restored.id == entry.id)
        }
        #expect(root.entry(named: "same.png") == nil)
        #expect(Set(root.entries.map { root.mediaKey($0, fallback: "same.png") }).count == count)
        let forgotten = try #require(root.entries.first)
        await root.removeHost(try #require(forgotten.hostID))
        #expect(root.entries.count == count - 1)
        #expect(!root.isLive(for: forgotten))
    }

    @Test("Model choice uses each host's memory verdict, and pinning narrows it")
    func modelCapacity() throws {
        let hosts = HostConnections(storage: nil, catalog: LibraryCatalog(libraryRoot: nil, filesRoot: nil),
            makeClient: { _ in MobilePreview.unpairedClient() })
        for selectable in [false, true] {
            var snapshot = try #require(MobilePreview.snapshot())
            snapshot.models = [ModelChoosingTests.model(isSelectable: selectable, note: selectable ? nil : "Needs 23 GB")]
            snapshot.availability = ["a-model": .init(.available)]
            let client = LinkClient.frozen(snapshot: snapshot, library: [])
            hosts.add(HostPreference(host: try #require(client.pairedHost)), client: client, frozen: true)
        }
        let dispatch = GenerationDispatch(hosts: hosts, root: nil)
        #expect(dispatch.canChooseModel("a-model"))
        #expect(dispatch.modelReadiness("a-model") == "Ready on 1 Macs")
        dispatch.destination = hosts.hosts[0].id
        #expect(!dispatch.canChooseModel("a-model"))
        #expect(dispatch.modelReadiness("a-model") == "Needs 23 GB")
        dispatch.destination = hosts.hosts[1].id
        #expect(dispatch.canChooseModel("a-model"))
        dispatch.destination = nil
        hosts.hosts[1].preference.enabled = false
        #expect(!dispatch.canChooseModel("a-model"))
    }

    @Test("An unreadable submission file disables sending instead of replacing unresolved assignments")
    func ledgerFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let hosts = HostConnections(storage: nil, catalog: LibraryCatalog(libraryRoot: nil, filesRoot: nil),
            makeClient: { _ in MobilePreview.unpairedClient() })
        let dispatch = GenerationDispatch(hosts: hosts, root: root)
        #expect(dispatch.isSending)
        #expect(dispatch.note != nil)
        #expect(FileManager.default.fileExists(atPath: root.path))
    }
}
