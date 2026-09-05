import Foundation
import Synchronization

/// A cancellable wait for an independently owned task. Canceling the waiter never cancels
/// the shared work; its owner decides whether any other consumer still needs it.
public final class TaskReceipt<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, any Error>?
        var result: Result<Value, any Error>?
    }
    private let state = Mutex(State())

    public init() {}

    public func value(of task: Task<Value, any Error>) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let result = state.withLock { state -> Result<Value, any Error>? in
                    if let result = state.result { return result }
                    state.continuation = continuation
                    return nil as Result<Value, any Error>?
                }
                if let result { continuation.resume(with: result) }
                else { Task { self.finish(await task.result) } }
            }
        } onCancel: { self.finish(.failure(CancellationError())) }
    }

    private func finish(_ result: Result<Value, any Error>) {
        let continuation = state.withLock { state in
            guard state.result == nil else { return nil as CheckedContinuation<Value, any Error>? }
            state.result = result
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}
