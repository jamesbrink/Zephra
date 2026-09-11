import Foundation
import Testing

@testable import ZephraMobile

/// The rule that decides what the phone writes when the Mac says something new.
@Suite("Bringing the cached library into line with the Mac")
struct LibrarySyncTests {
    @Test("An empty cache takes everything the Mac has")
    func everythingIsNew() {
        let remote = [LibraryFixtures.entry("a.png"), LibraryFixtures.entry("b.png")]

        let plan = LibrarySync.plan(remote: remote, local: [])

        #expect(plan.upsert.map(\.fileName) == ["a.png", "b.png"])
        #expect(plan.remove.isEmpty)
    }

    @Test("A cache that already agrees is left alone")
    func nothingToDo() {
        let remote = [LibraryFixtures.entry("a.png")]
        let local = remote.map(CachedEntry.init)

        #expect(LibrarySync.plan(remote: remote, local: local).isEmpty)
    }

    @Test("A file whose modification time moved is taken in again")
    func staleByTime() {
        let local = [LibraryFixtures.cached("a.png")]
        let remote = [
            LibraryFixtures.entry("a.png", modifiedAt: Date(timeIntervalSince1970: 1_772_000_900))
        ]

        let plan = LibrarySync.plan(remote: remote, local: local)

        #expect(plan.upsert.map(\.fileName) == ["a.png"])
        #expect(plan.remove.isEmpty)
    }

    @Test("A file whose size moved is taken in again")
    func staleBySize() {
        let local = [LibraryFixtures.cached("a.png", fileSize: 100)]
        let remote = [LibraryFixtures.entry("a.png", fileSize: 200)]

        #expect(LibrarySync.plan(remote: remote, local: local).upsert.count == 1)
    }

    /// Favoriting a picture on the Mac rewrites its PNG, so its modification time moves and
    /// its version with it. That is the whole reason an annotation change reaches the phone,
    /// and it is worth a test of its own.
    @Test("An annotation change is a change, because it moves the file's fingerprint")
    func annotationIsAChange() {
        let local = [LibraryFixtures.cached("a.png")]
        let remote = [
            LibraryFixtures.entry(
                "a.png", modifiedAt: Date(timeIntervalSince1970: 1_772_000_060), favourite: true)
        ]

        let plan = LibrarySync.plan(remote: remote, local: local)

        #expect(plan.upsert.count == 1)
        #expect(plan.upsert.first?.annotation.isFavourite == true)
        #expect(local.first?.version != plan.upsert.first?.version, "the fingerprint moved")
    }

    @Test("A picture the Mac no longer lists is named for removal")
    func gone() {
        let local = [LibraryFixtures.cached("a.png"), LibraryFixtures.cached("b.png")]
        let remote = [LibraryFixtures.entry("a.png")]

        let plan = LibrarySync.plan(remote: remote, local: local)

        #expect(plan.upsert.isEmpty)
        #expect(plan.remove == ["b.png"])
    }

    @Test("Both at once: one changed, one new, one gone")
    func allThree() {
        let local = [
            LibraryFixtures.cached("a.png", fileSize: 100),
            LibraryFixtures.cached("b.png"),
        ]
        let remote = [
            LibraryFixtures.entry("a.png", fileSize: 200),
            LibraryFixtures.entry("c.png"),
        ]

        let plan = LibrarySync.plan(remote: remote, local: local)

        #expect(Set(plan.upsert.map(\.fileName)) == ["a.png", "c.png"])
        #expect(plan.remove == ["b.png"])
    }
}
