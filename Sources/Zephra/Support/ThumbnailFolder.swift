import CoreGraphics
import Foundation

/// The thumbnails that survive a relaunch, on disk under the app's caches folder.
///
/// An actor because it is a shared folder and the gate below has to mean something: baking a
/// 1024-pixel PNG down to a thumbnail costs a decode of the whole picture, and a grid flung
/// past two hundred images would otherwise ask for two hundred of those at once and spend the
/// scroll in the allocator. Four at a time keeps every core busy without any of them fighting.
///
/// Nothing here is on the main actor and nothing here returns to it: the decode happens in a
/// detached task and hands back a `CGImage`, which is immutable and so may cross.
actor ThumbnailFolder {
    /// Where the baked files live.
    let directory: URL

    /// How many bakes may run at once.
    private static let concurrentBakes = 4
    /// How long a thumbnail nothing has asked for is kept.
    static let keepFor: TimeInterval = 30 * 24 * 60 * 60

    private var baking = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var hasSwept = false

    /// A folder under the user's caches, which is the right place: every file in it can be
    /// rebuilt from the picture it came from, so the system is welcome to delete the lot.
    init(directory: URL = ThumbnailFolder.defaultDirectory()) {
        self.directory = directory
    }

    /// The thumbnail for one image at one size, read from the folder when it is there and baked
    /// when it is not. Nil when the file cannot be read at all.
    func image(for key: ThumbnailKey, of url: URL, pixels: Int) async -> CGImage? {
        let file = fileURL(for: key)
        if let cached = await Task.detached(priority: .utility, operation: {
            Self.read(file)
        }).value {
            return cached
        }
        await enterGate()
        defer { leaveGate() }
        return await Task.detached(priority: .utility) {
            Self.bake(url, pixels: pixels, to: file)
        }.value
    }

    /// Deletes everything nothing has asked for in thirty days. Runs once per launch and does
    /// its own listing off the main actor; a second call in the same session does nothing.
    func sweep(now: Date = Date()) async {
        guard !hasSwept else { return }
        hasSwept = true
        let directory = directory
        let cutoff = now.addingTimeInterval(-Self.keepFor)
        await Task.detached(priority: .background) {
            Self.discardEntries(under: directory, lastUsedBefore: cutoff)
        }.value
    }

    /// Where one key's file goes: a folder per leading byte, so no single directory holds the
    /// whole cache.
    func fileURL(for key: ThumbnailKey) -> URL {
        directory
            .appending(path: key.shard, directoryHint: .isDirectory)
            .appending(path: "\(key.hex).heic")
    }

    /// `~/Library/Caches/io.zephra.Zephra/Thumbnails`, or the temporary directory on the
    /// machine that somehow has no caches folder.
    static func defaultDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return caches
            .appending(path: "io.zephra.Zephra", directoryHint: .isDirectory)
            .appending(path: "Thumbnails", directoryHint: .isDirectory)
    }

    /// Waits until fewer than four bakes are running.
    private func enterGate() async {
        guard baking >= Self.concurrentBakes else {
            baking += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
        baking += 1
    }

    /// Lets the next waiting bake through.
    private func leaveGate() {
        baking -= 1
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume()
    }
}
