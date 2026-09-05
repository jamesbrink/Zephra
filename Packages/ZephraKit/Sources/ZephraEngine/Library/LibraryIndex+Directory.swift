import Foundation

extension LibraryIndex {
    /// Stops watching and waits for every queued write and scan. What Quit awaits, after the
    /// store's own shutdown, so an annotation toggled a moment before quitting reaches its
    /// file. Nothing rescans or inserts afterwards: the index is dead from here.
    public func shutdown() async {
        isLive = false
        await quiesce()
    }

    /// Stops new mutations and waits for every existing writer and independent scan.
    func pauseForDirectoryChange() async {
        isChangingDirectory = true
        directoryEpoch += 1
        await quiesce()
    }

    /// Cancels the watch and its debounce, then waits for the write chain and every scan.
    private func quiesce() async {
        debounce?.cancel()
        debounce = nil
        for watch in watches.values { watch.cancel() }
        watches.removeAll()
        await work?.value
        for task in activeScans.values { await task.value }
        isScanning = false
    }

    /// Keeps the observable identity used by every window while replacing its disk snapshot.
    func adoptDirectory(_ library: ImageLibrary) {
        self.library = library
        scan = LibraryScan(library: library, calendar: scan.calendar)
        items = []
        albums = []
        pending = [:]
        fingerprint = 0
        lastFailure = nil
        if case .album = query.scope { query.scope = .all }
        reproject()
    }

    func resumeAfterDirectoryChange() async {
        isChangingDirectory = false
        await rescanNow()
        if hasStarted { watchFolders() }
    }
}
