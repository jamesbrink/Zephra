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
        // What each scan found is deliberately dropped: this is a wait for the folder to be
        // quiet, and whatever a scan still in flight read belongs to the folder being left.
        for task in activeScans.values { _ = await task.value }
        isScanning = false
    }

    /// Keeps the observable identity the window and Settings share while replacing its disk
    /// snapshot. The undo stack goes with the old folder: every entry on it names files that
    /// are no longer indexed.
    func adoptDirectory(_ library: ImageLibrary) {
        self.library = library
        scan = LibraryScan(library: library, calendar: scan.calendar)
        items = []
        albums = []
        pending = [:]
        undoManager?.removeAllActions(withTarget: self)
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
