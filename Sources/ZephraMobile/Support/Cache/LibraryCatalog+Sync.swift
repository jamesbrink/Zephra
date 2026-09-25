import Foundation
import Observation
import ZephraLinkClient

/// Following the client, and writing what it says to disk.
///
/// `withObservationTracking` fires once and has to be re-armed, so this is a loop: arm, wait,
/// sync, arm again. The callback runs *before* the change lands, which is why nothing is read
/// inside it — the loop reads the client after the wait returns, by which time the new value
/// is there.
extension LibraryCatalog {
    /// What is on disk, published before anything is asked of the Mac.
    ///
    /// This is the whole of the offline promise: a phone opened in a tunnel draws the library
    /// from here, and the client's own list arrives later or not at all. Under a frozen preview
    /// state the stores keep nothing, so the fixture's entries are seeded straight in instead.
    func loadFromDisk(seeding client: LinkClient) async {
        let generation = epoch
        let stored = await entryStore.load()
        guard generation == epoch, !Task.isCancelled else { return }
        if stored.isEmpty {
            let seeded = client.library.map { CachedEntry($0, hostID: hostID) }
            publish(seeded)
            // Writing the seed down is the point: a client that answered before this loop
            // armed — pairing's own client, which has a library pulled by the time its host
            // row exists — would otherwise live in memory only, because the next sync
            // compares itself against what was published here and sees no change to make.
            await entryStore.save(seeded)
        } else {
            publish(stored)
        }
        await measureCache()
    }

    /// Watches the client for as long as the task lives.
    func follow(_ client: LinkClient) async {
        while !Task.isCancelled {
            let changes = changes(in: client)
            await sync(with: client)
            var iterator = changes.makeAsyncIterator()
            _ = await iterator.next()
            await Task.yield()
        }
    }

    /// Brings the cache into line with what the client is holding.
    ///
    /// The removals are applied only when what the client holds covers the whole folder, which
    /// is `LinkClient.libraryIsComplete`: the pull that follows every connect has read the last
    /// page. The Mac sends at most a hundred entries in a reset
    /// (`CompanionPublication.resetThreshold`), so a phone that took every reset as gospel would
    /// throw the rest of its cache away the first time somebody with two thousand pictures
    /// rescanned a folder — and would lose the library offline, which is the one thing the cache
    /// is for.
    func sync(with client: LinkClient) async {
        let generation = epoch
        isLive = client.connection.isLive
        changed?()
        let remote = client.library
        let whole = client.libraryIsComplete
        guard !remote.isEmpty || whole else { return }

        if whole { await adoptLegacy(remote) }
        guard generation == epoch, !Task.isCancelled else { return }
        let plan = LibrarySync.plan(remote: remote, local: entries)
        let removals = whole ? plan.remove : []
        guard !plan.upsert.isEmpty || !removals.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false; changed?() }
        let taken = plan.upsert.map { CachedEntry($0, hostID: hostID) }
        var held = Dictionary(entries.map { ($0.fileName, $0) }, uniquingKeysWith: { _, last in last })
        for entry in taken { held[entry.fileName] = entry }
        for name in removals { held[name] = nil }
        publish(Array(held.values))

        guard generation == epoch else { return }
        await entryStore.save(taken)
        await entryStore.remove(removals)
        await measureCache()
    }

    /// Waits for the client's library or its connection to be about to change.
    ///
    /// All three in one arming, because all three decide what a library surface draws: the
    /// entries are the pictures, the connection is whether favoriting one is offered or greyed,
    /// and completeness is whether a picture the Mac no longer lists may be forgotten.
    private func changes(in client: LinkClient) -> AsyncStream<Void> {
        AsyncStream<Void> { sink in
            withObservationTracking {
                _ = client.library
                _ = client.connection
                _ = client.libraryIsComplete
            } onChange: {
                sink.yield(())
                sink.finish()
            }
        }
    }
}
