import Foundation
import Testing
import ZephraTestSupport
@testable import ZephraMobile

@MainActor @Suite("Media operations own their files and report outcomes")
struct MediaActionTests {
    @Test("A save holds its own lease through clearing and rejects duplicate presses")
    func savingAcrossClear() async throws {
        let scratch = Scratch("SavingAcrossClear")
        let store = FileStore(root: scratch.root)
        let url = try #require(await store.store(Data([1]), as: "a.png"))
        let (blocked, finish) = AsyncStream<Void>.makeStream()
        defer { finish.finish() }
        var saves = 0
        let action = MediaAction(save: { file, _ in
            saves += 1
            for await _ in blocked {}
            #expect(FileManager.default.fileExists(atPath: file.path))
        })
        let task = Task { await action.savePhoto(isVideo: false) {
            LeasedMedia(url: url, lease: await store.lease("a.png"))
        } }
        for _ in 0..<1000 { if saves == 1 { break }; await Task.yield() }
        #expect(saves == 1 && action.busy)
        await store.clear()
        await action.savePhoto(isVideo: false) { throw CancellationError() }
        #expect(saves == 1)
        finish.finish(); await task.value
        #expect(action.message == "Picture saved to Photos.")
        for _ in 0..<1000 {
            if await store.url(for: "a.png") == nil { break }; await Task.yield()
        }
        #expect(await store.url(for: "a.png") == nil)
    }

    @Test("Permission refusal is shown and cancellation stays quiet")
    func failures() async throws {
        let scratch = Scratch("PhotoFailures")
        let store = FileStore(root: scratch.root)
        let action = MediaAction(save: { _, _ in throw PhotosSaver.Failure.notAllowed })
        await action.savePhoto(isVideo: false) {
            LeasedMedia(url: scratch.url("a.png"), lease: await store.lease("a.png"))
        }
        #expect(action.message == PhotosSaver.Failure.notAllowed.localizedDescription)
        #expect(!action.busy)
        await action.share { throw CancellationError() }
        #expect(action.message == nil && !action.busy && action.sharing == nil)
        await action.share { throw PhotosSaver.Failure.refused("Fetch failed") }
        #expect(action.message == "Fetch failed")
    }

    @Test("A share presentation holds a lease until dismissed")
    func shareLease() async throws {
        let scratch = Scratch("SharingLease")
        let store = FileStore(root: scratch.root)
        let url = try #require(await store.store(Data([1]), as: "a.png"))
        let action = MediaAction()
        await action.share { LeasedMedia(url: url, lease: await store.lease("a.png")) }
        await store.clear()
        #expect(FileManager.default.fileExists(atPath: url.path))
        action.sharing = nil
        for _ in 0..<1000 { if await store.url(for: "a.png") == nil { break }; await Task.yield() }
        #expect(await store.url(for: "a.png") == nil)
    }
}
