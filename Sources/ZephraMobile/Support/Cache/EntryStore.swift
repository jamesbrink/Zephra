import Foundation
import ZephraLinkProtocol
import os

/// The library as the phone last heard it, one JSON file per picture under
/// `Application Support/Library/Entries/`.
///
/// A file each rather than one list, because the two things that happen to this folder are a
/// handful of entries changing and a handful going away: rewriting a thousand-entry document
/// to record that one picture became a favorite is a write the size of the library for a
/// change the size of a bool. The name is the picture's own name, so an entry and its file are
/// filed under the same word and there is no second index to keep in step.
///
/// An actor because every one of these calls touches the disk, and the surfaces that ask are
/// on the main actor drawing at sixty frames a second.
actor EntryStore {
    /// Where the files are, or nil for a store that writes nothing.
    ///
    /// Nil under a frozen preview state: a screenshot build is handed the fixture's entries
    /// and must write none of them, since the simulator's container outlives the launch and a
    /// photographed library that persisted would not be the same library twice.
    private let directory: URL?
    private let logger = Logger(subsystem: "io.zephra", category: "mobile.cache")

    /// A store under one library root, or one that keeps nothing.
    init(root: URL?) {
        directory = root?.appending(path: "Entries", directoryHint: .isDirectory)
        if let directory { try? CacheDirectories.prepare(directory) }
    }

    /// Everything the phone is holding, newest first.
    ///
    /// An unreadable file is dropped with a log line rather than taken as a reason to throw:
    /// one corrupted entry out of a thousand is one picture missing from a grid, and the next
    /// sync writes it again.
    func load() -> [CachedEntry] {
        guard let directory else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: directory.path(percentEncoded: false))) ?? []
        var entries: [CachedEntry] = []
        for name in names where name.hasSuffix(".json") {
            let url = directory.appending(path: name)
            guard let data = try? Data(contentsOf: url),
                let entry = try? Self.decoder.decode(CachedEntry.self, from: data)
            else {
                logger.notice("A cached library entry would not decode and was dropped.")
                try? FileManager.default.removeItem(at: url)
                continue
            }
            entries.append(entry)
        }
        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    /// Writes these entries, replacing whatever was filed under their names.
    func save(_ entries: [CachedEntry]) {
        guard let directory else { return }
        for entry in entries {
            guard let data = try? Self.encoder.encode(entry) else { continue }
            try? data.write(to: url(for: entry.fileName, in: directory), options: .atomic)
        }
    }

    /// Forgets these pictures.
    func remove(_ fileNames: [String]) {
        guard let directory else { return }
        for name in fileNames {
            try? FileManager.default.removeItem(at: url(for: name, in: directory))
        }
    }

    /// Empties the folder.
    func clear() {
        guard let directory else { return }
        CacheDirectories.empty(directory)
    }

    /// How many bytes the entries occupy.
    func size() -> Int64 {
        directory.map(CacheDirectories.size(of:)) ?? 0
    }

    /// Where one picture's entry is filed.
    private func url(for fileName: String, in directory: URL) -> URL {
        directory.appending(path: "\(fileName).json")
    }

    /// The wire's own coding, so a cached file reads as exactly what a Mac would send.
    private static let decoder = LinkJSON.decoder()
    private static let encoder = LinkJSON.encoder()
}
