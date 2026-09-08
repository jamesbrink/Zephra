import ZephraEngine

/// What pressing Delete means, which depends on where you are standing.
///
/// In the app rather than in the engine, because it is a decision about the interface: the
/// engine offers "move to Recently Deleted" and "delete for good" as two plain operations, and
/// which of them a keystroke means — and whether to ask first — is a question about what is on
/// screen. Three places ask it, so it is answered once here.
extension LibraryIndex {
    /// Deletes the images, into Recently Deleted from anywhere else and for good from inside
    /// it, asking only in the second case.
    /// `async` because the second case asks first, and asking is a sheet on the window the
    /// question is about rather than a dialog floating free of it. The first case awaits
    /// nothing: moving to Recently Deleted never asks.
    func delete(_ ids: Set<LibraryItem.ID>) async {
        guard !ids.isEmpty else { return }
        guard query.scope == .recentlyDeleted else {
            moveToRecentlyDeleted(ids)
            return
        }
        guard await PurgeConfirmation.confirm(count: ids.count) else { return }
        purge(ids)
    }
}
