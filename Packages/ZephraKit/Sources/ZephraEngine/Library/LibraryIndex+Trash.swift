import Foundation

/// Moving images between the library and Recently Deleted, and emptying it.
///
/// A move changes the file's path, which is its identity here, so these do not try to patch the
/// item in place: the images leave the index at once and the rescan that follows the move puts
/// them back under their new collection. One directory listing per delete, not one per image.
extension LibraryIndex {
    /// Moves images into Recently Deleted, where they wait thirty days.
    public func moveToRecentlyDeleted(_ ids: Set<LibraryItem.ID>) {
        move(ids, action: .delete) { library, url in
            try library.moveToRecentlyDeleted(url)
        }
    }

    /// Moves images back out of Recently Deleted, into the library.
    public func restore(_ ids: Set<LibraryItem.ID>) {
        move(ids, action: .restore) { library, url in
            try library.restoreFromRecentlyDeleted(url)
        }
    }

    /// Deletes images for good, without waiting for their thirty days.
    public func purge(_ ids: Set<LibraryItem.ID>) {
        move(ids, action: .purge) { library, url in
            try library.discard(url)
            return url
        }
    }

    /// Discards everything whose thirty days are up. Called on a scan; safe to call at any time,
    /// because the manifest, not this, decides what is old enough.
    public func purgeExpired(now: Date = Date()) {
        let library = library
        enqueue {
            let cutoff = now.addingTimeInterval(-RecentlyDeletedManifest.grace)
            let purged = await Task.detached(priority: .utility) { () -> Int in
                ((try? library.purgeRecentlyDeleted(deletedBefore: cutoff, now: now)) ?? []).count
            }.value
            guard purged > 0 else { return }
            await self.rescanNow()
        }
    }

    /// The shape all three share: take the images out of the index, do the file work in order,
    /// then read the folders back so they reappear wherever they now are.
    private func move(
        _ ids: Set<LibraryItem.ID>,
        action: LibraryFailure.Action,
        _ operation: @escaping @Sendable (ImageLibrary, URL) throws -> URL
    ) {
        let moving = items.filter { ids.contains($0.id) }.map(\.url)
        guard !moving.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        reproject()
        let library = library
        enqueue {
            let failures = await Task.detached(priority: .utility) { () -> [(String, String)] in
                var failures: [(String, String)] = []
                for url in moving {
                    do {
                        _ = try operation(library, url)
                    } catch {
                        failures.append((url.path(percentEncoded: false), error.localizedDescription))
                    }
                }
                return failures
            }.value
            if let failure = failures.first {
                self.lastFailure = LibraryFailure(
                    itemID: failure.0, action: action, reason: failure.1)
            }
            await self.rescanNow()
        }
    }
}
