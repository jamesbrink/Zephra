import Foundation
import Testing
@testable import ZephraMobile

@MainActor @Suite("Storage refresh cleanup belongs to the current request")
struct StorageRefreshTests {
    @Test("Cancelled success resets loading without publishing an error")
    func cancelledSuccess() async {
        let storage = RemoteModelStorage()
        let task = Task { await storage.refresh {
            withUnsafeCurrentTask { $0?.cancel() }
            return []
        } }
        await task.value
        #expect(!storage.loading && storage.failure == nil)
    }

    @Test("An older refresh cannot clear a newer request's loading state")
    func superseded() async {
        let storage = RemoteModelStorage()
        let (first, releaseFirst) = AsyncStream<Void>.makeStream()
        let (second, releaseSecond) = AsyncStream<Void>.makeStream()
        defer { releaseFirst.finish(); releaseSecond.finish() }
        let old = Task { await storage.refresh { for await _ in first {}; return [] } }
        for _ in 0..<1000 { if storage.loading { break }; await Task.yield() }
        var newStarted = false
        let new = Task { await storage.refresh { newStarted = true; for await _ in second {}; return [] } }
        for _ in 0..<1000 { if newStarted { break }; await Task.yield() }
        releaseFirst.finish(); await old.value
        #expect(storage.loading)
        releaseSecond.finish(); await new.value
        #expect(!storage.loading)
    }
}
