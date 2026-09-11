import Foundation
import Testing
import ZephraTestSupport

@testable import ZephraMobile

/// Whole pictures and clips on the phone, and the budget that decides which of them stay.
@Suite("The phone's file cache")
struct FileStoreTests {
    @Test("A file kept is a file found again")
    func roundTrip() async throws {
        let scratch = Scratch("FileStore")
        let store = FileStore(root: scratch.root)

        let written = await store.store(Data("pixels".utf8), as: "a.png")

        #expect(written != nil)
        let found = try #require(await store.url(for: "a.png"))
        #expect(try Data(contentsOf: found) == Data("pixels".utf8))
        #expect(await store.url(for: "b.png") == nil)
    }

    @Test("The size is what the folder holds")
    func size() async {
        let scratch = Scratch("FileStore")
        let store = FileStore(root: scratch.root)

        await store.store(Data(count: 400), as: "a.png")
        await store.store(Data(count: 600), as: "b.png")

        #expect(await store.size() == 1000)
    }

    @Test("Past the budget, the least recently read goes first")
    func trimsByAccessDate() async throws {
        let scratch = Scratch("FileStore")
        let store = FileStore(root: scratch.root, limit: 1000)

        await store.store(Data(count: 400), as: "old.png")
        await store.store(Data(count: 400), as: "middle.png")
        // Reading one is what keeps it: the oldest *read* goes, not the oldest written.
        _ = await store.url(for: "old.png")
        await store.store(Data(count: 400), as: "new.png")

        #expect(await store.url(for: "middle.png") == nil, "the one nothing looked at")
        #expect(await store.url(for: "old.png") != nil, "read again, so kept")
        #expect(await store.url(for: "new.png") != nil)
        #expect(await store.size() <= 1000)
    }

    @Test("Under the budget nothing is dropped")
    func keepsWhatFits() async {
        let scratch = Scratch("FileStore")
        let store = FileStore(root: scratch.root, limit: 1_000_000)

        for index in 0..<5 { await store.store(Data(count: 1000), as: "\(index).png") }

        #expect(await store.size() == 5000)
    }

    @Test("Clearing it leaves nothing")
    func clears() async {
        let scratch = Scratch("FileStore")
        let store = FileStore(root: scratch.root)

        await store.store(Data(count: 1000), as: "a.png")
        await store.clear()

        #expect(await store.size() == 0)
        #expect(await store.url(for: "a.png") == nil)
    }

    @Test("A store with nowhere to write keeps nothing and says so")
    func frozen() async {
        let store = FileStore(root: nil)

        #expect(await store.store(Data(count: 10), as: "a.png") == nil)
        #expect(await store.url(for: "a.png") == nil)
        #expect(await store.size() == 0)
    }

    @Test("The budget itself drops least recently read first, and only what it must")
    func budgetIsPure() {
        let files = (0..<4).map { index in
            CacheBudget.File(
                url: URL(filePath: "/tmp/\(index)"), size: 300,
                accessedAt: Date(timeIntervalSince1970: Double(index)))
        }

        let dropped = CacheBudget.excess(of: files, limit: 1000)

        #expect(dropped.map(\.url.lastPathComponent) == ["0"], "one is enough to fit")
        #expect(CacheBudget.excess(of: files, limit: 1200).isEmpty)
        #expect(CacheBudget.excess(of: files, limit: 300).count == 3)
    }

    /// A clip is two files under one stem, and it is the MP4 the phone shares and saves.
    @Test("A clip's file is the MP4 beside its poster")
    func clipNames() {
        #expect(LibraryCatalog.clipName(of: "2026-09-11 09-12-03 wan.png") == "2026-09-11 09-12-03 wan.mp4")
    }
}
