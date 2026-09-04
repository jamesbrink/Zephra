import Foundation
import Testing

@testable import ZephraCore

@Suite("Download retry")
struct DownloadRetryTests {
    private struct Broken: Error, Equatable { let code: Int }

    @Test("a transfer that breaks is tried again, and its result returned once it holds")
    func retriesUntilItWorks() async throws {
        var calls = 0
        let result = try await DownloadRetry.run(
            pause: { _ in .zero }, isPermanent: { _ in false }
        ) {
            calls += 1
            if calls < 3 { throw Broken(code: calls) }
            return "done"
        }
        #expect(result == "done")
        #expect(calls == 3)
    }

    @Test("the tries run out, and the last error is the one reported")
    func givesUpAfterTheAttempts() async {
        var calls = 0
        await #expect(throws: Broken(code: 4)) {
            try await DownloadRetry.run(
                attempts: 4, pause: { _ in .zero }, isPermanent: { _ in false }
            ) {
                calls += 1
                throw Broken(code: calls)
            }
        }
        #expect(calls == 4)
    }

    @Test("a permanent error stops the retrying at once")
    func stopsOnAPermanentError() async {
        var calls = 0
        await #expect(throws: Broken(code: 401)) {
            try await DownloadRetry.run(
                pause: { _ in .zero },
                isPermanent: { ($0 as? Broken)?.code == 401 }
            ) {
                calls += 1
                throw Broken(code: 401)
            }
        }
        #expect(calls == 1, "a refused token is not a connection that dropped")
    }

    @Test("cancellation passes through without another try")
    func cancellationIsNotRetried() async {
        var calls = 0
        await #expect(throws: CancellationError.self) {
            try await DownloadRetry.run(pause: { _ in .zero }, isPermanent: { _ in false }) {
                calls += 1
                throw CancellationError()
            }
        }
        #expect(calls == 1)
    }

    @Test("each retry is announced with the attempt about to run and the error before it")
    func announcesEachRetry() async throws {
        var announced: [Int] = []
        var calls = 0
        _ = try await DownloadRetry.run(
            pause: { _ in .zero },
            isPermanent: { _ in false },
            onRetry: { attempt, _ in announced.append(attempt) }
        ) {
            calls += 1
            if calls < 3 { throw Broken(code: calls) }
        }
        #expect(announced == [2, 3])
    }

    @Test("the pause doubles from two seconds and stops growing at sixteen")
    func pauseGrowsThenHolds() {
        #expect(DownloadRetry.pause(before: 2) == .seconds(2))
        #expect(DownloadRetry.pause(before: 3) == .seconds(4))
        #expect(DownloadRetry.pause(before: 4) == .seconds(8))
        #expect(DownloadRetry.pause(before: 5) == .seconds(16))
        #expect(DownloadRetry.pause(before: 9) == .seconds(16))
    }
}

@Suite("Download retry under a stop")
struct DownloadRetryStopTests {
    private struct Broken: Error {}

    @Test("a transfer that broke because it was stopped is not announced as a retry")
    func stopIsNotARetry() async {
        let announced = Announcements()
        let task = Task {
            try await DownloadRetry.run(
                pause: { _ in .zero }, isPermanent: { _ in false },
                onRetry: { attempt, _ in announced.add(attempt) }
            ) {
                withUnsafeCurrentTask { $0?.cancel() }
                throw Broken()
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(announced.attempts.isEmpty)
    }

    private final class Announcements: @unchecked Sendable {
        private(set) var attempts: [Int] = []
        func add(_ attempt: Int) { attempts.append(attempt) }
    }
}
