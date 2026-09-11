import Foundation
import Testing
import ZephraEngine
@testable import ZephraLinkProtocol

@Suite("A library entry carries the picture's own two chunks and a version to cache by")
struct LibraryEntryTests {
    @Test("An entry survives being written and read back")
    func entryRoundTrips() throws {
        #expect(try LinkFixtures.roundTrip(LinkFixtures.entry) == LinkFixtures.entry)
    }

    @Test("The record and the annotation cross as themselves")
    func chunksAreTheRealTypes() throws {
        var entry = LinkFixtures.entry
        entry.annotation = LibraryAnnotation(isFavourite: true, tags: ["dusk"], albums: [])
        let read = try LinkFixtures.roundTrip(entry)
        #expect(read.annotation.isFavourite)
        #expect(read.annotation.tags == ["dusk"])
        #expect(read.record?.prompt == "a lighthouse")
        #expect(read.record?.seed == 42)
    }

    @Test("A file Zephra did not make has no record and is still an entry")
    func importedFileHasNoRecord() throws {
        let entry = LibraryEntry(
            fileName: "photo.png", record: nil, annotation: .none, isVideo: false,
            createdAt: LinkFixtures.date, width: 800, height: 600, fileSize: 100,
            contentModifiedAt: LinkFixtures.date)
        #expect(try LinkFixtures.roundTrip(entry).record == nil)
    }

    @Test("The version follows the name, the time and the size and nothing else")
    func versionFollowsTheFile() {
        let base = LibraryEntry.version(
            fileName: "a.png", contentModifiedAt: LinkFixtures.date, fileSize: 100)
        #expect(base.count == 16)
        #expect(
            base == LibraryEntry.version(
                fileName: "a.png", contentModifiedAt: LinkFixtures.date, fileSize: 100))
        #expect(
            base != LibraryEntry.version(
                fileName: "b.png", contentModifiedAt: LinkFixtures.date, fileSize: 100))
        #expect(
            base != LibraryEntry.version(
                fileName: "a.png", contentModifiedAt: LinkFixtures.date, fileSize: 101))
        #expect(
            base != LibraryEntry.version(
                fileName: "a.png",
                contentModifiedAt: LinkFixtures.date.addingTimeInterval(1), fileSize: 100))
    }

    @Test("An entry computes its own version when it is not given one")
    func entryComputesItsVersion() {
        #expect(
            LinkFixtures.entry.version
                == LibraryEntry.version(
                    fileName: "lighthouse.png", contentModifiedAt: LinkFixtures.date,
                    fileSize: 2048))
    }

    @Test("The file name is the entry's identity, since no path ever crosses")
    func nameIsTheIdentity() {
        #expect(LinkFixtures.entry.id == "lighthouse.png")
    }
}
