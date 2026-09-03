import Foundation
import Synchronization
import Testing

@testable import ZephraEngine

/// A watch has to outlive its folder: a rename, a Finder move, an ejected volume.
@Suite("A folder watch that outlives its folder")
struct LibraryFolderWatchTests {
    @Test("a write in the folder is noticed")
    func noticesAWrite() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let changes = Mutex(0)
        let watch = LibraryFolderWatch(url: folder) { changes.withLock { $0 += 1 } }
        defer { watch.cancel() }

        try Data("one".utf8).write(to: folder.appending(path: "one.txt"))
        try await Self.waitFor(changes, toReach: 1)
        #expect(changes.withLock { $0 } >= 1)
        #expect(!watch.isCancelled)
    }

    @Test("a folder renamed away and back is watched again, and the wait says so")
    func survivesARename() async throws {
        let folder = try Self.folder()
        let away = folder.deletingLastPathComponent()
            .appending(path: folder.lastPathComponent + "-away", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: away)
        }
        let changes = Mutex(0)
        let watch = LibraryFolderWatch(
            url: folder, firstRetry: .milliseconds(10), maximumRetry: .milliseconds(40)
        ) { changes.withLock { $0 += 1 } }
        defer { watch.cancel() }

        // Away for long enough that the reopen has to fail and be retried.
        try FileManager.default.moveItem(at: folder, to: away)
        try await Task.sleep(for: .milliseconds(60))
        try FileManager.default.moveItem(at: away, to: folder)
        // The retry that finds the folder again reports a change of its own, because everything
        // that happened while it was away went unseen.
        try await Self.waitFor(changes, toReach: 1)
        let afterRename = changes.withLock { $0 }

        try Data("two".utf8).write(to: folder.appending(path: "two.txt"))
        try await Self.waitFor(changes, toReach: afterRename + 1)
        #expect(changes.withLock { $0 } > afterRename, "and it is watching the folder again")
    }

    @Test("a cancelled watch stops, and says it has")
    func cancelling() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let changes = Mutex(0)
        let watch = LibraryFolderWatch(url: folder) { changes.withLock { $0 += 1 } }

        watch.cancel()
        #expect(watch.isCancelled)
        try Data("three".utf8).write(to: folder.appending(path: "three.txt"))
        try await Task.sleep(for: .milliseconds(80))
        #expect(changes.withLock { $0 } == 0)
    }

    private static func waitFor(_ changes: borrowing Mutex<Int>, toReach target: Int) async throws {
        for _ in 0..<400 where changes.withLock({ $0 }) < target {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func folder() throws -> URL {
        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "LibraryFolderWatchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
