import Foundation

/// Filling the index from the folders, and noticing when they change.
extension LibraryIndex {
    /// What one scan came back with, off the main actor.
    struct Scanned: Sendable {
        let items: [LibraryItem]
        let albums: [Album]
        let fingerprint: Int
    }

    /// Reads the library once and starts watching it. Idempotent: calling it again does nothing.
    public func start() {
        guard isLive, !hasStarted else { return }
        hasStarted = true
        watchFolders()
        enqueue { await self.rescanNow() }
        purgeExpired()
    }

    /// Reads the folders now, reusing every item whose file has not moved.
    ///
    /// Public because there are two things a folder watch cannot see — a volume that was
    /// unmounted while the app slept, and a change the watch's debounce coalesced away — and
    /// because a refresh command should be able to say so.
    public func rescanNow() async {
        guard isLive else { return }
        isScanning = true
        scanCount += 1
        let scan = scan
        let known = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let scanned = await Task.detached(priority: .utility) { () -> Scanned in
            // The fingerprint is taken first: a change during the scan then shows up as a
            // difference next time rather than being read and forgotten.
            let fingerprint = scan.fingerprint()
            let items = scan.rescan(known: known)
            return Scanned(
                items: items,
                albums: scan.library.albums(reconciledWith: items),
                fingerprint: fingerprint
            )
        }.value
        adopt(scanned)
        isScanning = false
        watchFolders()
    }

    /// Adds one file to the index without rescanning: one header read and a sorted insert.
    ///
    /// This is what a finished generation calls. A rescan would be correct too, and on a folder
    /// of ten thousand images it would also be a directory listing every time an image is saved.
    /// The albums are left alone: a file that has only just been written is in none of them.
    public func insert(fileAt url: URL) {
        guard isLive else { return }
        let standardized = url.standardizedFileURL
        let collection = library.scanRoots.first {
            $0.url.standardizedFileURL == standardized.deletingLastPathComponent()
        }?.collection ?? .generated
        guard let listing = scan.listing(of: standardized),
              let item = scan.item(listing, in: collection)
        else { return }
        items.removeAll { $0.id == item.id }
        let position = items.firstIndex { $0.createdAt < item.createdAt } ?? items.count
        items.insert(item, at: position)
        reproject()
    }

    /// The folder watch's handler: wait for things to stop moving, then look, and only rescan
    /// when the folders actually differ from what is held. Zephra's own writes come back through
    /// here too, and this is what stops each of them costing a scan.
    func folderChanged() {
        debounce?.cancel()
        debounce = Task { [settleFor] in
            try? await Task.sleep(for: settleFor)
            guard !Task.isCancelled else { return }
            // Behind the writes, not beside them: a scan that read a file Zephra was halfway
            // through annotating would show the old answer and then have to be told again.
            self.enqueue { await self.rescanIfChanged() }
            self.purgeExpired()
        }
    }

    /// Rescans only if the folders' fingerprint has moved.
    func rescanIfChanged() async {
        guard isLive else { return }
        let scan = scan
        let now = await Task.detached(priority: .utility) { scan.fingerprint() }.value
        guard now != fingerprint else { return }
        await rescanNow()
    }

    /// Watches every folder that exists. Called again after each scan, so the Recently Deleted
    /// folder starts being watched the first time something is deleted into it.
    func watchFolders() {
        for root in library.scanRoots
        where watches[root.collection] == nil || watches[root.collection]?.isCancelled == true {
            var isDirectory: ObjCBool = false
            let path = root.url.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { continue }
            watches[root.collection] = LibraryFolderWatch(url: root.url) { [weak self] in
                Task { @MainActor in self?.folderChanged() }
            }
        }
    }

    private func adopt(_ scanned: Scanned) {
        items = scanned.items.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
        }
        albums = scanned.albums
        fingerprint = scanned.fingerprint
        reproject()
    }
}
