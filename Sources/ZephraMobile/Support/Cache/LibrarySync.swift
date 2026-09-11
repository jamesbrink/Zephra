import Foundation
import ZephraLinkProtocol

/// What the phone has to write to agree with what the Mac just said.
nonisolated struct SyncPlan: Hashable, Sendable {
    /// The entries to take in: ones the cache has never seen, and ones whose file has moved.
    var upsert: [LibraryEntry]
    /// The file names the cache should forget.
    var remove: [String]

    /// A plan, empty by default.
    init(upsert: [LibraryEntry] = [], remove: [String] = []) {
        self.upsert = upsert
        self.remove = remove
    }

    /// Whether there is nothing to do, which is the usual answer.
    var isEmpty: Bool { upsert.isEmpty && remove.isEmpty }
}

/// Comparing what the Mac published against what the phone is holding.
///
/// A pure function, so the rule that decides whether a thumbnail is still good is a thing that
/// can be tested rather than a thing that is watched for in a grid. It is deliberately not
/// aware of the disk: the catalog applies what this answers, and the stores do as they are
/// told.
nonisolated enum LibrarySync {
    /// The writes that would bring `local` into line with `remote`.
    ///
    /// An entry is taken in when the cache has never heard of it, and again whenever the file
    /// behind it has moved — which `CachedEntry.isStale(against:)` decides from the same three
    /// facts `LibraryEntry.version` is made of. Favoriting a picture on the Mac rewrites its
    /// PNG, so its modification time moves and the entry arrives here as a change.
    ///
    /// The removals are every name the cache holds that `remote` does not. **That is only the
    /// truth when `remote` is the whole library**: the Mac sends at most a hundred entries in
    /// a reset, so `LibraryCatalog` applies the removals only when what arrived covers the
    /// folder, and otherwise keeps what it has. The rule lives there, with the count that
    /// decides it, rather than being pushed in here as a flag.
    static func plan(remote: [LibraryEntry], local: [CachedEntry]) -> SyncPlan {
        let held = Dictionary(local.map { ($0.fileName, $0) }, uniquingKeysWith: { first, _ in first })
        let arrived = Set(remote.map(\.fileName))
        let upsert = remote.filter { entry in
            guard let cached = held[entry.fileName] else { return true }
            return cached.isStale(against: entry)
        }
        let remove = local.map(\.fileName).filter { !arrived.contains($0) }
        return SyncPlan(upsert: upsert, remove: remove)
    }
}
