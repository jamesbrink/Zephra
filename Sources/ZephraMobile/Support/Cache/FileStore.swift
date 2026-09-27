import Foundation

/// Whole pictures and clips, under `Caches/Files/`.
///
/// The name on disk is the name in the Mac's library folder, and a clip's MP4 sits beside its
/// poster under the same stem — `VideoSidecar`'s rule, which is the Mac's rule, so a phone and
/// a Mac never disagree about where a clip is. Two files for one picture, and the budget
/// weighs both.
///
/// In Caches rather than Application Support because these are the bytes that can always be
/// fetched again: iOS may take the folder back under pressure and nothing is lost but a wait.
/// `CacheBudget` empties it first, least recently read going first.
actor FileStore {
    /// Where the files are, or nil for a store that keeps nothing.
    let directory: URL?
    /// What the folder may hold. A parameter only so a test can fill it without half a
    /// gigabyte of fixtures.
    private let limit: Int64
    var leases: [String: Int] = [:]
    var pendingDeletion: Set<String> = []
    var generations: [String: UUID] = [:]
    var generation = UUID()
    var revision = 0
    var subscribers: [UUID: AsyncStream<Int>.Continuation] = [:]

    /// A store under one caches root.
    init(root: URL?, limit: Int64 = CacheBudget.bytes) {
        directory = root
        self.limit = limit
        if let root { try? CacheDirectories.prepare(root) }
    }

    /// The file already held under this name, or nil. Reading one marks it as read, which is
    /// what keeps it: the budget drops whatever has gone longest unlooked-at.
    func url(for fileName: String) -> URL? {
        guard let url = path(for: fileName),
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return nil }
        touch(url)
        return url
    }

    /// The bytes already held under this name, or nil, read on this actor rather than on the
    /// main one: a picture off a Mac is megabytes, and reading it where the interface runs is a
    /// dropped frame. Reading marks the file as read, exactly as `url(for:)` does.
    func data(for fileName: String) -> Data? {
        guard let url = url(for: fileName) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Keeps one file's bytes and answers where they landed, trimming the folder afterwards if
    /// it has grown past the budget.
    @discardableResult
    func store(_ data: Data, as fileName: String, ticket: UUID? = nil) -> URL? {
        guard ticket == nil || ticket == self.ticket(for: fileName) else { return nil }
        if pendingDeletion.contains(fileName), leases[fileName, default: 0] > 0 {
            return url(for: fileName)
        }
        guard let url = path(for: fileName) else { return nil }
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        touch(url)
        trim()
        publishChange()
        return url
    }

    func remove(prefix: String) {
        for key in generations.keys where key.hasPrefix(prefix) { generations[key] = UUID() }
        guard let directory else { return }
        for file in Self.contents(of: directory) where file.url.lastPathComponent.hasPrefix(prefix) {
            discard(file.url)
        }
        publishChange()
    }

    /// Consumers keep their URLs until their final lease ends.
    func clear() {
        generation = UUID(); generations.removeAll()
        guard let directory else { return }
        for file in Self.contents(of: directory) { discard(file.url) }
        publishChange()
    }

    private func discard(_ url: URL) {
        let key = url.lastPathComponent
        if leases[key, default: 0] > 0 { pendingDeletion.insert(key) }
        else { try? FileManager.default.removeItem(at: url); pendingDeletion.remove(key) }
    }

    /// How many bytes the files occupy.
    func size() -> Int64 {
        directory.map(CacheDirectories.size(of:)) ?? 0
    }

    /// Drops least recently read files until the folder fits.
    func trim() {
        guard let directory else { return }
        for file in CacheBudget.excess(of: Self.contents(of: directory).filter { leases[$0.url.lastPathComponent, default: 0] == 0 },
            limit: max(0, limit - Self.contents(of: directory).filter { leases[$0.url.lastPathComponent, default: 0] > 0 }.reduce(0) { $0 + $1.size })) {
            try? FileManager.default.removeItem(at: file.url)
            pendingDeletion.remove(file.url.lastPathComponent)
            publishChange()
        }
    }

    func lease(_ key: String) -> FileLease {
        leases[key, default: 0] += 1
        return FileLease(key: key, store: self)
    }
    func release(_ key: String) {
        leases[key] = max(0, leases[key, default: 0] - 1)
        if leases[key] == 0 {
            leases.removeValue(forKey: key)
            if pendingDeletion.remove(key) != nil, let url = path(for: key) {
                try? FileManager.default.removeItem(at: url)
                publishChange()
            }
        }
        trim()
    }

}
