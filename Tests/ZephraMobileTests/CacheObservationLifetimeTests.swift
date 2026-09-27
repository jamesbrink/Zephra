import Foundation
import Testing
@testable import ZephraMobile

@MainActor @Suite("Released catalogs settle cache revision subscriptions")
struct CacheObservationLifetimeTests {
    @Test("A stopped catalog releases its shared file-store observer on deinit")
    func releasedCatalog() async throws {
        let files = FileStore(root: nil)
        var catalog: LibraryCatalog? = LibraryCatalog(libraryRoot: nil, filesRoot: nil, sharedFiles: files)
        weak var released = catalog
        try await settle { await files.subscribers.count == 1 }
        catalog?.stop()
        catalog = nil
        #expect(released == nil)
        try await settle { await files.subscribers.isEmpty }
    }

    private func settle(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw CancellationError() }
            await Task.yield()
        }
    }
}
