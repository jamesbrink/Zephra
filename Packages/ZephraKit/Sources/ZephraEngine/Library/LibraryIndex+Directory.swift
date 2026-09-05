import Foundation

extension LibraryIndex {
    /// Stops new mutations and waits for every existing writer and independent scan.
    func pauseForDirectoryChange() async {
        isChangingDirectory = true
        directoryEpoch += 1
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
