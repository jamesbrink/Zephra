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

    /// A gate every tail read waits at once one is set, so a test can act on the store while
    /// a pass sits between passes.
    final class TailGate: @unchecked Sendable {
        private let lock = NSLock()
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var opened = false
        private var arrived = false

        /// True once a tail read is waiting here.
        var isWaiting: Bool { lock.withLock { arrived && !opened } }

        func wait() async {
            await withCheckedContinuation { continuation in
                lock.lock()
                arrived = true
                if opened {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                waiters.append(continuation)
                lock.unlock()
            }
        }

        /// Lets every waiting read, and every later one, through.
        func open() {
            let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                opened = true
                defer { waiters = [] }
                return waiters
            }
            for continuation in waiting { continuation.resume() }
        }
    }

    private let storage = NSLock()
    private var calls = Calls()
    private var gate: TailGate?

    /// Holds every tail read at `gate` until the test opens it.
    func hold(at gate: TailGate) { storage.withLock { self.gate = gate } }

    var recorded: Calls { storage.withLock { calls } }

    func update(_ change: (inout Calls) -> Void) { storage.withLock { change(&calls) } }

    func tail(of url: URL, frames: Int) async throws -> [Data] {
        await storage.withLock { gate }?.wait()
        return try read(frames: frames, fromFile: true)
    }

    func tail(ofData mp4: Data, frames: Int) async throws -> [Data] {
        await storage.withLock { gate }?.wait()
        return try read(frames: frames, fromFile: false)
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
