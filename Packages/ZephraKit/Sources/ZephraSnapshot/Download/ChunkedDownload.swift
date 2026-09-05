import Foundation
import Synchronization

/// One HTTP GET handed back as its bytes arrive.
///
/// `URLSession` offers a whole `Data` or a file it wrote itself; neither will do here. A model
/// shard is twelve gigabytes, so it cannot be held in memory, and it has to be appended to the
/// `.incomplete` file as it comes so that a transfer stopped half-way resumes from what is
/// there. So the body is delivered chunk by chunk through the data delegate, which is also
/// where cancellation gets its chance: the reader checks between chunks.
///
/// The delegate is called as fast as the network delivers and the stream it feeds has no
/// bound of its own, so a fast connection writing to a slow disk would pile the difference up
/// in memory. The transfer is suspended once `highWater` bytes are waiting to be written and
/// resumed when the writer has drained it below `lowWater`; `ChunkedBody` is what tells this
/// object a chunk has been taken. Nothing is dropped, because no model byte may be.
///
/// One of these serves a whole session; the task identifier is what tells its transfers apart.
/// `@unchecked Sendable` because `URLSession` calls the delegate on its own queue: every stored
/// thing is inside the mutex, which is the checking the compiler cannot do for us.
final class ChunkedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// Bytes waiting to be written above which the transfer is paused.
    static let highWater = 64 << 20
    /// Bytes waiting below which a paused transfer is resumed.
    static let lowWater = 16 << 20

    /// What one transfer is waiting on: the headers, then the body, and how much of the body
    /// the writer has not taken yet.
    private struct Pending {
        var task: URLSessionDataTask
        var response: CheckedContinuation<HTTPURLResponse, any Error>?
        var chunks: AsyncThrowingStream<Data, any Error>.Continuation?
        var buffered = 0
        var suspended = false
    }

    private let pending = Mutex<[Int: Pending]>([:])

    /// Starts `request` and returns the response headers with the body still arriving.
    ///
    /// The caller must consume or drop the body; dropping it cancels the transfer, which is
    /// what makes an abandoned download stop moving bytes rather than run to the end unread.
    func start(_ request: URLRequest, on session: URLSession) async throws -> (
        HTTPURLResponse, ChunkedBody
    ) {
        try Task.checkCancellation()
        let cancellation = Mutex(false)
        let task = session.dataTask(with: request)
        let (stream, chunks) = AsyncThrowingStream<Data, any Error>.makeStream()
        chunks.onTermination = { _ in task.cancel() }
        let response: HTTPURLResponse = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                cancellation.withLock { cancelled in
                    guard !cancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    pending.withLock {
                        $0[task.taskIdentifier] = Pending(task: task, response: continuation, chunks: chunks)
                    }
                    task.resume()
                }
            }
        } onCancel: {
            cancellation.withLock { cancelled in
                cancelled = true
                task.cancel()
            }
        }
        return (response, ChunkedBody(stream: stream, download: self, task: task.taskIdentifier))
    }

    /// Notes that the writer has taken `bytes` of the body, resuming a transfer paused for
    /// want of room.
    func drained(_ bytes: Int, task identifier: Int) {
        pending.withLock { state in
            guard var entry = state[identifier] else { return }
            entry.buffered = max(0, entry.buffered - bytes)
            if entry.suspended && entry.buffered < Self.lowWater {
                // Resumed inside the lock, with the books: see `didReceive`.
                entry.suspended = false
                entry.task.resume()
            }
            state[identifier] = entry
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let waiting = pending.withLock { state -> CheckedContinuation<HTTPURLResponse, any Error>? in
            let continuation = state[dataTask.taskIdentifier]?.response
            state[dataTask.taskIdentifier]?.response = nil
            return continuation
        }
        guard let http = response as? HTTPURLResponse else {
            waiting?.resume(throwing: ModelDownloadError.interrupted(reason: "The server answered with something that was not HTTP."))
            completionHandler(.cancel)
            return
        }
        waiting?.resume(returning: http)
        completionHandler(.allow)
    }

    nonisolated func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data
    ) {
        let chunks = pending.withLock { state -> AsyncThrowingStream<Data, any Error>.Continuation? in
            guard var entry = state[dataTask.taskIdentifier] else { return nil }
            entry.buffered += data.count
            if !entry.suspended && entry.buffered > Self.highWater {
                // Suspended inside the lock, and before the chunk is handed over. The task's
                // pause and the books saying it is paused have to change together: a writer
                // draining between the two could resume the task and then watch this suspend
                // it, with `suspended` false and so nothing left to ever resume it. `suspend`
                // and `resume` are counted and thread-safe and call nothing back, so the lock
                // is the right place for them.
                entry.suspended = true
                entry.task.suspend()
            }
            state[dataTask.taskIdentifier] = entry
            return entry.chunks
        }
        chunks?.yield(data)
    }

    nonisolated func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
        let finished = pending.withLock { $0.removeValue(forKey: task.taskIdentifier) }
        // A transfer that failed before its headers arrived has to fail the wait for them;
        // one that failed afterwards fails the stream the caller is already reading.
        if let waiting = finished?.response {
            waiting.resume(throwing: error ?? ModelDownloadError.interrupted(reason: "The connection ended before the server answered."))
        }
        finished?.chunks?.finish(throwing: error)
    }
}
