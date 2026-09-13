import Foundation

/// Keeps a consumer's file available until the viewer, share sheet or save finishes.
nonisolated final class FileLease: Sendable {
    let key: String
    let store: FileStore
    init(key: String, store: FileStore) { self.key = key; self.store = store }
    deinit { let key = key, store = store; Task { await store.release(key) } }
}
