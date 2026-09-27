import Foundation
import Testing
import ZephraLinkProtocol
import ZephraLinkClient
import ZephraTestSupport
@testable import ZephraMobile

@MainActor @Suite("Catalog clear serializes host ownership and admitted work")
struct CacheTransactionTests {
    @Test("Clear cancels an admitted operation before draining it")
    func cancellingRequests() async throws {
        let catalog = LibraryCatalog(libraryRoot: nil, filesRoot: nil)
        let (blocked, release) = AsyncStream<Void>.makeStream()
        defer { release.finish() }
        var entered = false
        let request = Task { try await catalog.request {
            entered = true
            for await _ in blocked {}
            return Data([1])
        } }
        try await settle { entered }
        await catalog.clearCache()
        await #expect(throws: CancellationError.self) { _ = try await request.value }
        #expect(catalog.requests.isEmpty && catalog.operations == 0 && !catalog.isClearing)
        catalog.stop()
    }

    @Test("Host removal waits for clearing and never restarts the removed catalog")
    func topology() async throws {
        let scratch = Scratch("ClearTopology")
        let root = LibraryCatalog(libraryRoot: scratch.root, filesRoot: nil)
        let snapshot = try #require(MobilePreview.snapshot())
        let client = LinkClient.frozen(snapshot: snapshot, library: MobilePreview.library())
        let a = try #require(client.hostID)
        let child = root.addHost(a, client: client, frozen: true)
        let gate = CacheTransactionGate()
        let request = Task { try await child.request { await gate.wait(); return Data() } }
        try await settle { gate.entered }
        let clear = Task { await root.clearCache() }
        try await settle { root.isClearing }
        let remove = Task { await root.removeHost(a) }
        let other = LinkClient.frozen(snapshot: snapshot, library: MobilePreview.library())
        let b = try #require(other.hostID)
        let added = root.addHost(b, client: other, frozen: true)
        #expect(added.isClearing)
        gate.release()
        _ = try? await request.value
        await clear.value; await remove.value
        #expect(root.children[a] == nil)
        #expect(child.observation == nil && child.isClearing)
        #expect(root.children[b] === added && !added.isClearing)
        await root.removeHost(b)
        root.stop()
    }

    private func settle(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CancellationError() }
            await Task.yield()
        }
    }
}
