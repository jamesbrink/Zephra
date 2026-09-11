import Foundation
import ZephraLinkClient

/// Favoriting, tagging and deleting, which are the three things the phone may change about a
/// picture.
///
/// Every one of them is the same shape, and it is the Mac's `LibraryIndex` shape: change what
/// is on screen first, tell the Mac, and put it back if the Mac says no. A star that waits for
/// a round trip over a relay before it fills in is a star that feels broken, and the change is
/// one bool.
///
/// The Mac is what writes: the annotation lives in the picture's own PNG, so the phone's copy
/// of an entry is a guess until the next sync brings the file's new fingerprint back. Nothing
/// here invents a version — see `CachedEntry.annotated`.
extension LibraryCatalog {
    /// Marks pictures as favorites, or unmarks them.
    @discardableResult
    func setFavourite(_ names: [String], on: Bool) async -> Bool {
        await edit(names, changing: { $0.annotated(favourite: on) }) { client in
            try await client.setFavourite(names: names, on: on)
        }
    }

    /// Replaces the tags on pictures.
    @discardableResult
    func setTags(_ names: [String], tags: [String]) async -> Bool {
        await edit(names, changing: { $0.annotated(tags: tags) }) { client in
            try await client.setTags(names: names, tags: tags)
        }
    }

    /// Moves pictures to the Mac's Recently Deleted, and takes them off this phone.
    ///
    /// The entries go on the way out rather than on the way back, so the grid closes over the
    /// gap at once; a refusal puts them back exactly where they were. The thumbnails and files
    /// are left alone: they are named by a fingerprint nothing will ask for again, and the
    /// budget sweeps them up in its own time rather than this having to find them.
    @discardableResult
    func delete(_ names: [String]) async -> Bool {
        guard let client, isLive else { return false }
        let gone = Set(names)
        let removed = entries.filter { gone.contains($0.fileName) }
        guard !removed.isEmpty else { return false }
        publish(entries.filter { !gone.contains($0.fileName) })
        do {
            try await client.delete(names)
            await entryStore.remove(names)
            await measureCache()
            return true
        } catch {
            logger.notice("The Mac would not delete: \(error.localizedDescription)")
            publish(entries + removed)
            return false
        }
    }

    /// One annotation edit: on screen, then over the wire, then back again on a refusal.
    private func edit(
        _ names: [String],
        changing: (CachedEntry) -> CachedEntry,
        sending: (LinkClient) async throws -> Void
    ) async -> Bool {
        guard let client, isLive else { return false }
        let touched = Set(names)
        let before = entries
        publish(entries.map { touched.contains($0.fileName) ? changing($0) : $0 })
        do {
            try await sending(client)
            await entryStore.save(entries.filter { touched.contains($0.fileName) })
            return true
        } catch {
            logger.notice("The Mac would not take an edit: \(error.localizedDescription)")
            publish(before)
            return false
        }
    }
}
