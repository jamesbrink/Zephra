import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol
@testable import ZephraMobile

/// The size Settings > Storage reads is the combined catalog's, and only a root re-count walks
/// the children's folders — so a host landing bytes on disk has to bring the root's number with
/// it, or a paired phone with a full cache reads "Empty" with Clear Cache disabled.
@MainActor
@Suite("The combined catalog reports the size it actually holds")
struct LibraryCacheSizeTests {
    @Test("A connected host's sync brings the combined count up from Empty")
    func connectedHostPopulatesTheCount() async throws {
        let bed = try Bed()
        let child = bed.root.addHost(bed.id, client: bed.connected(), frozen: false)

        // Nothing calls sync by hand: `addHost` starts the child, and the child's own load and
        // follow loop are what take the frozen client's library and write it down — the
        // launched phone's path.
        await reached { bed.root.cacheBytes > 0 }

        #expect(bed.root.cacheBytes > 0, "Settings must not read Empty over a synced cache")
        #expect(!bed.root.entries.isEmpty)
        #expect(
            await child.entryStore.load().count == MobilePreview.library().count,
            """
            what the client already held when the host row was added must be written down, \
            not just published — the next sync sees no change against it
            """)
        await child.stopAndDrain()
        bed.close()
    }

    @Test("An offline cold launch counts what survived on disk")
    func offlineLaunchCountsWhatIsOnDisk() async throws {
        let bed = try Bed()
        let written = bed.root.addHost(bed.id, client: MobilePreview.unpairedClient(), frozen: false)
        await written.stopAndDrain()
        let entry = CachedEntry(LibraryFixtures.cached("kept.png").entry, hostID: bed.id)
        await written.entryStore.save([entry])

        // The next launch, with no Mac in reach: the host's disk read is all there is.
        let reopened = LibraryCatalog(libraryRoot: bed.library, filesRoot: bed.files)
        let child = reopened.addHost(bed.id, client: MobilePreview.unpairedClient(), frozen: false)

        await reached { reopened.cacheBytes > 0 }

        #expect(reopened.cacheBytes > 0, "the cache is on disk whatever the wire cannot confirm")
        await child.stopAndDrain()
        bed.close()
    }

    @Test("Forgetting the only host takes its bytes out of the count")
    func forgettingTheHostEmptiesTheCount() async throws {
        let bed = try Bed()
        let child = bed.root.addHost(bed.id, client: bed.connected(), frozen: false)
        await reached { bed.root.cacheBytes > 0 }
        #expect(bed.root.cacheBytes > 0)

        await bed.root.removeHost(bed.id)
        await reached { bed.root.cacheBytes == 0 }

        #expect(bed.root.cacheBytes == 0, "what was deleted must not keep being counted")
        _ = child
        bed.close()
    }

    /// A scratch pair of cache roots and one host identity.
    private struct Bed {
        let directory: URL
        let root: LibraryCatalog
        let id: HostID

        var library: URL { directory.appending(path: "Library") }
        var files: URL { directory.appending(path: "Files") }

        init() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            self.directory = directory
            root = LibraryCatalog(
                libraryRoot: directory.appending(path: "Library"),
                filesRoot: directory.appending(path: "Files"))
            id = HostID(keys: DeviceIdentity().publicKeys)
        }

        /// A paired, live client holding the preview fixture's library.
        func connected() -> LinkClient {
            LinkClient.frozen(
                snapshot: MobilePreview.snapshot()!, library: MobilePreview.library())
        }

        func close() { try? FileManager.default.removeItem(at: directory) }
    }

    /// Waits for the coalesced re-count to land; the debounce is 75 ms, so this is seconds of
    /// slack, not a guess at timing.
    private func reached(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
