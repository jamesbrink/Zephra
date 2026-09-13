import Foundation

/// A launch that pretends this Mac has never run Zephra: its own preferences, its own models
/// folder and its own image library, all under one throwaway directory.
///
/// `ZEPHRA_FRESH_START=<directory>` is what asks for it, and `make run-fresh` is how it is
/// usually asked for. It exists because the first ten minutes are the hardest part of the app
/// to look at: with a models folder full of packed variants and a library of a thousand
/// pictures, there is no way to see what somebody opening Zephra for the first time sees —
/// the empty canvas, the model picker quoting a download, the fetch of a prebuilt variant
/// from the mirror, the first build, the first image.
///
/// Everything the launch remembers is redirected rather than cleared, so a person's real
/// preferences, models and pictures are never touched: `AppSettings.store` writes to a suite
/// of its own, and the two folder defaults answer with this directory's instead of
/// Application Support and `~/Pictures/Zephra`. What is *not* redirected is the Hugging Face
/// cache, which is a read-only fallback a real new Mac may equally have.
///
/// Read from the process environment here, as `InterfacePreview` reads its own switch, rather
/// than from the composition root: both answer questions asked while the root is still being
/// built.
struct FreshStart: Equatable, Sendable {
    /// The throwaway directory everything this launch keeps lives under.
    let root: URL

    /// This launch's, or nil for an ordinary one.
    static let current = resolve(ProcessInfo.processInfo.environment)

    /// The fresh start an environment asks for, if it asks for one. Pure, so it is tested.
    static func resolve(_ environment: [String: String]) -> FreshStart? {
        guard let path = environment["ZEPHRA_FRESH_START"], !path.isEmpty else { return nil }
        return FreshStart(root: URL(filePath: path, directoryHint: .isDirectory))
    }

    /// Where models are downloaded and built, in place of Application Support.
    var models: URL { root.appending(path: "Models", directoryHint: .isDirectory) }

    /// The image library, in place of `~/Pictures/Zephra`.
    var images: URL { root.appending(path: "Images", directoryHint: .isDirectory) }

    /// What every fresh start's preferences domain is named after.
    static let suitePrefix = "io.zephra.Zephra.fresh"

    /// The preferences domain this launch reads and writes: one per directory.
    ///
    /// It was one name for every fresh start once, on the reasoning that a fresh start is
    /// thrown away and `make run-fresh` empties the domain before it launches. Two fresh
    /// starts at once is what that misses — a screenshot build beside a UAT one, two agents,
    /// or simply a second directory launched by hand — and the second launch then inherits the
    /// first's answers: its chooser is already answered, its model already chosen. That is not
    /// a new Mac, and on the day it happened the "new Mac" started downloading a model nobody
    /// had picked. The directory is what a fresh start *is*, so the directory names its
    /// preferences.
    var defaultsSuite: String { "\(Self.suitePrefix).\(Self.fingerprint(of: root))" }

    /// The file that records which directory's preferences have been written, and so whether
    /// this directory has been launched before. Removing the directory removes it, which is
    /// what `make run-fresh`'s reset does and what makes the next launch a first one.
    var suiteStamp: URL { root.appending(path: ".zephra-fresh-preferences") }

    /// This launch's preferences, emptied first when the directory has never been launched.
    ///
    /// The reset a person asks for is `rm -rf` of the directory (`FRESH_RESET=1`, the
    /// default), and the domain has to go with it or the answers outlive the folder. The stamp
    /// inside the directory is what says the two are in step: gone, and the domain is emptied
    /// before a single preference is read; present, and `FRESH_RESET=0` keeps what is there,
    /// which is how a session is resumed without fetching gigabytes again.
    func preferences() -> UserDefaults? {
        guard let suite = UserDefaults(suiteName: defaultsSuite) else { return nil }
        guard !FileManager.default.fileExists(atPath: suiteStamp.path(percentEncoded: false))
        else { return suite }
        suite.removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? Data(defaultsSuite.utf8).write(to: suiteStamp)
        return suite
    }

    /// A short, stable name for one directory. Stable is the whole of it: Swift's own hashing
    /// is seeded per process, so a domain named from it would be a different domain at every
    /// launch. FNV-1a over the path is written out here for that reason. The path is
    /// standardized and its trailing slash dropped, so `/tmp/fresh`, `/tmp/fresh/` and
    /// `/tmp/./fresh` are one directory with one set of preferences; symbolic links are
    /// deliberately not followed, since that answer would change the day the directory is
    /// created and move a launch's preferences out from under it.
    static func fingerprint(of root: URL) -> String {
        var path = root.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x1000_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
