import Foundation
import Testing
import ZephraTestSupport

@testable import ZephraEngine

extension ImageLibraryMigrationTests {
    @Test("a source-only deletion manifest cannot expire a foreign destination picture")
    func staleManifestCannotAdoptForeignImage() throws {
        let scratch = Scratch("ImageStaleManifest")
        let manifest = RecentlyDeletedManifest(entries: [
            .init(fileName: "ghost.png", deletedAt: .distantPast)
        ])
        let manifestPath = "Recently Deleted/" + RecentlyDeletedManifest.fileName
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(manifest)
        try bytes.write(to: scratch.make("old/" + manifestPath))
        try MockBackend.pngData.write(to: scratch.make("new/Recently Deleted/ghost.png"))

        #expect(throws: ImageDirectoryError.self) {
            try ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("new")).run()
        }
        #expect(try Data(contentsOf: scratch.url("old/" + manifestPath)) == bytes)
        #expect(try Data(contentsOf: scratch.url("new/Recently Deleted/ghost.png")) == MockBackend.pngData)
        #expect(!scratch.hasFile("new/" + manifestPath))
    }

    @Test("noncolliding owned and foreign destination PNGs refuse library merging")
    func noncollidingDestinationImages() throws {
        for directory in ["", "Sources/", "Recently Deleted/"] {
            for owned in [false, true] {
                let scratch = Scratch("ImageDestinationPictures")
                let original = try Self.fixture(scratch, path: "old/original.png")
                let path = "new/" + directory + "other.PNG"
                let existing: Data
                if owned { existing = try Self.fixture(scratch, path: path) }
                else {
                    existing = MockBackend.pngData
                    try existing.write(to: scratch.make(path))
                }
                #expect(throws: ImageDirectoryError.self) {
                    try ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("new")).run()
                }
                #expect(try Data(contentsOf: scratch.url("old/original.png")) == original)
                #expect(try Data(contentsOf: scratch.url(path)) == existing)
                #expect(!scratch.hasFile("new/original.png"))
            }
        }
    }

    @Test("unrelated destination files still permit a library move")
    func unrelatedDestinationFiles() throws {
        let scratch = Scratch("ImageDestinationNotes")
        let original = try Self.fixture(scratch)
        for path in ["notes.txt", "Sources/notes.txt", "Recently Deleted/notes.txt"] {
            try scratch.write("keep", to: "new/" + path)
        }
        #expect(try ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("new")).run().isEmpty)
        #expect(try Data(contentsOf: scratch.url("new/image.png")) == original)
        for path in ["notes.txt", "Sources/notes.txt", "Recently Deleted/notes.txt"] {
            #expect(try String(contentsOf: scratch.url("new/" + path), encoding: .utf8) == "keep")
        }
    }
}
