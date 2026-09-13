import Foundation
import Testing
import ZephraLinkProtocol
@testable import ZephraMobile

@MainActor @Suite("Combined cached library qualification measurements")
struct LibraryPerformanceTests {
    @Test func eightThousandCachedEntries() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = directory.appending(path: "Library"), files = directory.appending(path: "Files")
        let ids = (0..<8).map { _ in HostID(keys: DeviceIdentity().publicKeys) }
        for id in ids {
            let entries = (0..<1000).map { number -> CachedEntry in
                var entry = LibraryFixtures.cached("picture-\(number).png").entry
                entry.createdAt = Date(timeIntervalSince1970: Double(number))
                return CachedEntry(entry, hostID: id)
            }
            await EntryStore(root: library.appending(path: "Hosts/" + id.rawValue)).save(entries)
        }
        let started = ContinuousClock.now
        let catalog = LibraryCatalog(libraryRoot: library, filesRoot: files)
        for id in ids { _ = catalog.addHost(id, client: MobilePreview.unpairedClient(), frozen: false) }
        try await MobileHostFixture.settle { catalog.entries.count == 8000 }
        let available = started.duration(to: .now)
        let queried = ContinuousClock.now
        let sections = catalog.sections
        let grouping = queried.duration(to: .now)
        #expect(!sections.isEmpty)
        #expect(Set(catalog.entries.map(\.id)).count == 8000)
        print("LIBRARY_PERFORMANCE hosts=8 entries=8000 coldMetadataReady=\(available) firstGrouping=\(grouping)")
        for id in ids { await catalog.removeHost(id) }
    }
}
