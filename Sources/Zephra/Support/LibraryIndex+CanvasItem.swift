import ZephraEngine

/// The one lookup that decides whether the picture on the canvas is a library image or not yet
/// one — a session's fresh picture, before the folder scan has caught up with the file it
/// wrote. `CanvasInspector` and the canvas's context menu both need the answer, and both need
/// it to be the same answer at the same moment, so it lives here rather than being worked out
/// twice.
extension LibraryIndex {
    /// The library's record of whatever `store.current` shows, by the file it was written to.
    func canvasItem(for store: GenerationStore) -> LibraryItem? {
        guard let url = store.current?.fileURL else { return nil }
        return item(for: url.standardizedFileURL.path(percentEncoded: false))
    }
}
