import Foundation
import ZephraCore

/// A clip reader and joiner that never touches AVFoundation: the tail is `count` copies of
/// the mock's PNG, and a join is the parts' bytes laid end to end behind a note of what was
/// dropped, so a test can read off what the store asked for.
final class MockClipEditing: ClipEditing, @unchecked Sendable {
    struct Calls: Sendable {
        var tailReads: [(frames: Int, fromFile: Bool)] = []
        var stitches: [[ClipPart]] = []
        /// When set, every tail read fails with it.
        var tailError: (any Error)?
        /// When set, every stitch fails with it.
        var stitchError: (any Error)?
    }

    private let storage = NSLock()
    private var calls = Calls()

    var recorded: Calls { storage.withLock { calls } }

    func update(_ change: (inout Calls) -> Void) { storage.withLock { change(&calls) } }

    func tail(of url: URL, frames: Int) async throws -> [Data] {
        try read(frames: frames, fromFile: true)
    }

    func tail(ofData mp4: Data, frames: Int) async throws -> [Data] {
        try read(frames: frames, fromFile: false)
    }

    private func read(frames: Int, fromFile: Bool) throws -> [Data] {
        let error = storage.withLock { calls.tailReads.append((frames, fromFile)); return calls.tailError }
        if let error { throw error }
        return Array(repeating: MockBackend.pngData, count: frames)
    }

    func stitch(_ parts: [ClipPart]) async throws -> Data {
        let error = storage.withLock { calls.stitches.append(parts); return calls.stitchError }
        if let error { throw error }
        var joined = Data("stitched:\(parts.map { "\($0.mp4.count)-\($0.dropLeading)" }.joined(separator: ","))|".utf8)
        for part in parts { joined.append(part.mp4) }
        return joined
    }
}
