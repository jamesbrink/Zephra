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
/// One of these serves a whole session; the task identifier is what tells its transfers apart.
/// `@unchecked Sendable` because `URLSession` calls the delegate on its own queue: every stored
/// thing is inside the mutex, which is the checking the compiler cannot do for us.
final class ChunkedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// What one transfer is waiting on: the headers, then the body.
    private struct Pending {
        var response: CheckedContinuation<HTTPURLResponse, any Error>?
        var chunks: AsyncThrowingStream<Data, any Error>.Continuation?
    }

    private let pending = Mutex<[Int: Pending]>([:])

    /// Starts `request` and returns the response headers with the body still arriving.
    ///
    /// The caller must consume or drop the stream; dropping it cancels the transfer, which is
    /// what makes an abandoned download stop moving bytes rather than run to the end unread.
    func start(_ request: URLRequest, on session: URLSession) async throws -> (
        HTTPURLResponse, AsyncThrowingStream<Data, any Error>
    ) {
        let task = session.dataTask(with: request)
        let (stream, chunks) = AsyncThrowingStream<Data, any Error>.makeStream()
        chunks.onTermination = { _ in task.cancel() }
        let response = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.withLock {
                    $0[task.taskIdentifier] = Pending(response: continuation, chunks: chunks)
                }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
        return (response, stream)
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
        pending.withLock { $0[dataTask.taskIdentifier]?.chunks }?.yield(data)
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
