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

    /// The preferences domain this launch reads and writes. One name rather than one per
    /// directory: a fresh start is meant to be thrown away, and `make run-fresh` empties this
    /// domain before it launches, so a stale one is never inherited.
    static let defaultsSuite = "io.zephra.Zephra.fresh"
}
