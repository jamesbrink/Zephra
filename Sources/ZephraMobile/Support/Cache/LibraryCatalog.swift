import Foundation
import ZephraLinkClient
import os

/// The Mac's library as the phone holds it: what it has been told, kept on disk, and browsable
/// with no Mac in reach.
///
/// The one object beside `LinkClient` that a library view observes, and the one exception to
/// "a view reads the Mac through the client". It holds no fact of its own that came over the
/// link — every entry in it arrived as a `LibraryEntry` and is kept exactly as it arrived —
/// it holds the *cache*, which is a fact about this phone. The folder on the Mac is the truth;
/// this is a copy that may be behind.
///
/// Split by concern like `GenerationStore` and `LinkClient`: syncing, media and editing are
/// each a file of their own, and a new concern is another extension rather than more lines
/// here.
@MainActor
@Observable
final class LibraryCatalog {
    /// Everything the phone is holding, newest first.
    private(set) var entries: [CachedEntry] = []
    /// What narrows what is on screen. The one thing a view writes.
    var query = CachedLibraryQuery()
    /// Whether a sync is writing to disk right now. Written by the sync loop and nothing else.
    var isSyncing = false
    /// How many bytes the three stores are holding between them, as of the last count.
    private(set) var cacheBytes: Int64 = 0
    /// Whether the Mac can be reached: what decides whether favoriting, tagging, deleting and
    /// the two fetches are offered or shown greyed. Written by the sync loop, which arms on
    /// the connection as well as on the library for exactly this.
    var isLive = false

    /// The pictures on screen, grouped into days. Recomputed from the query, so no view ever
    /// filters — the Mac's rule, for the Mac's reason.
    var sections: [CachedSection] { query.sections(of: entries) }

    @ObservationIgnored let entryStore: EntryStore
    @ObservationIgnored let thumbnailStore: ThumbnailStore
    @ObservationIgnored let fileStore: FileStore
    @ObservationIgnored private(set) var client: LinkClient?
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored let logger = Logger(subsystem: "io.zephra", category: "mobile.library")

    /// A catalog over three stores.
    ///
    /// The roots ride in so a test can point the whole thing at a scratch directory, and so a
    /// frozen preview state can pass nil and write nothing at all.
    init(libraryRoot: URL?, filesRoot: URL?) {
        entryStore = EntryStore(root: libraryRoot)
        thumbnailStore = ThumbnailStore(root: libraryRoot)
        fileStore = FileStore(root: filesRoot)
    }

    /// The catalog this launch gets: the real folders, or nothing under a frozen preview
    /// state, where the fixture's entries are seeded straight in and no byte is written.
    convenience init() {
        let frozen = MobilePreview.state != nil
        self.init(
            libraryRoot: frozen ? nil : try? CacheDirectories.library(),
            filesRoot: frozen ? nil : try? CacheDirectories.files())
    }

    /// Reads what is on disk, then follows the client for as long as the app runs.
    ///
    /// Idempotent: the composition root calls it once, and calling it again is a no-op rather
    /// than a second loop over the same client.
    func start(client: LinkClient) {
        guard observation == nil else { return }
        attach(client)
        observation = Task { [weak self] in
            guard let self else { return }
            await self.loadFromDisk(seeding: client)
            await self.follow(client)
        }
    }

    /// Takes the client without starting the loop.
    ///
    /// `start` calls it first; a suite that drives the catalog by hand calls it instead, so
    /// nothing is arming and re-arming behind the assertions.
    func attach(_ client: LinkClient) {
        self.client = client
        isLive = client.connection.isLive
    }

    /// Stops following. Nothing calls it in the app — the catalog lives as long as the process
    /// — but a test that has finished with one should not leave a loop running behind it.
    func stop() {
        observation?.cancel()
        observation = nil
    }

    /// One picture by name, which is how a menu, the viewer and a run's strip find one.
    func entry(named fileName: String) -> CachedEntry? {
        entries.first { $0.fileName == fileName }
    }

    /// Every tag anything in the cache carries, in alphabetical order, which is what the tag
    /// sheet offers before anything is typed.
    var knownTags: [String] {
        Array(Set(entries.flatMap(\.tags))).sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    /// Puts the entries in the order the grid wants them and publishes them.
    func publish(_ entries: [CachedEntry]) {
        self.entries = entries.sorted { $0.createdAt > $1.createdAt }
    }

    /// Counts what the three stores hold. Off the main actor, since it walks three folders.
    func measureCache() async {
        async let entries = entryStore.size()
        async let thumbnails = thumbnailStore.size()
        async let files = fileStore.size()
        cacheBytes = await entries + thumbnails + files
    }

    /// Forgets everything: the entries, the thumbnails and the files.
    ///
    /// The library comes back on the next sync, since the Mac is the truth and the phone only
    /// ever held a copy — which is what makes this safe to offer as a button in Settings.
    func clearCache() async {
        await entryStore.clear()
        await thumbnailStore.clear()
        await fileStore.clear()
        entries = []
        await measureCache()
        if let client { await sync(with: client) }
    }
}
