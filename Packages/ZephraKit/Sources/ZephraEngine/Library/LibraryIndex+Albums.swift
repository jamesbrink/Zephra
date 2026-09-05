import Foundation

/// Making, renaming and emptying albums.
///
/// A rename writes the manifest and no picture: the manifest is where the current name lives,
/// and rewriting a thousand images to change a word would be a thousand writes for nothing.
/// Deleting an album does write its members, because an id still named by a picture is an album
/// the next scan would recreate.
extension LibraryIndex {
    /// Makes an album and returns it, so the caller can put something in it straight away.
    @discardableResult
    public func createAlbum(named name: String) -> Album {
        let album = Album(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !isChangingDirectory else { return album }
        albums = sorted(albums + [album])
        reproject()
        writeAlbumsBehindTheQueue()
        return album
    }

    /// Renames an album. No image is rewritten: the copy of the name each one carries is a
    /// fallback for a lost manifest, and it is allowed to be behind.
    public func renameAlbum(_ album: Album, to name: String) {
        guard !isChangingDirectory else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = albums.firstIndex(where: { $0.id == album.id })
        else { return }
        albums[index].name = trimmed
        albums = sorted(albums)
        reproject()
        writeAlbumsBehindTheQueue()
    }

    /// Removes an album and takes its images out of it. The images themselves are untouched
    /// otherwise: an album is a grouping, not a folder.
    public func deleteAlbum(_ album: Album) {
        guard !isChangingDirectory else { return }
        albums.removeAll { $0.id == album.id }
        let members = Set(
            items.filter { item in item.annotation.albums.contains { $0.id == album.id } }.map(\.id))
        annotate(members) { $0.albums.removeAll { $0.id == album.id } }
        reproject()
        writeAlbumsBehindTheQueue()
    }

    /// Puts every image in `ids` into an album, if it is not in it already.
    public func add(_ ids: Set<LibraryItem.ID>, to album: Album) {
        annotate(ids) { annotation in
            guard !annotation.albums.contains(where: { $0.id == album.id }) else { return }
            annotation.albums.append(
                LibraryAnnotation.Membership(id: album.id, name: album.name))
        }
    }

    /// Takes every image in `ids` out of an album.
    public func remove(_ ids: Set<LibraryItem.ID>, from album: Album) {
        annotate(ids) { $0.albums.removeAll { $0.id == album.id } }
    }

    /// The name an album goes by now, which is the manifest's, not whatever an image last
    /// recorded. Everything on screen should read a name through here.
    public func name(of id: UUID) -> String? {
        albums.first { $0.id == id }?.name
    }

    /// Queues the manifest write with the list as it is now, and counts it as pending until it
    /// lands. The list is captured here rather than read when the write runs: a rescan the
    /// folder watch queued in between reads the manifest still on disk, and `adopt` must not
    /// let that older list stand in for an edit that has not been written yet — or the write
    /// would put the old name back and the rename would be lost for good.
    private func writeAlbumsBehindTheQueue() {
        let snapshot = albums
        pendingAlbumWrites += 1
        enqueue {
            await self.writeAlbums(snapshot)
            self.pendingAlbumWrites -= 1
        }
    }

    private func writeAlbums(_ albums: [Album]) async {
        let library = library
        let reason = await Task.detached(priority: .utility) { () -> String? in
            do {
                try library.writeAlbums(albums)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        guard let reason else { return }
        lastFailure = LibraryFailure(itemID: nil, action: .album, reason: reason)
    }

    private func sorted(_ albums: [Album]) -> [Album] {
        albums.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedSame
                ? $0.createdAt < $1.createdAt
                : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
