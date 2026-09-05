import Foundation
import Testing
import ZephraTestSupport

@testable import ZephraEngine

@MainActor
@Suite("Image library migration")
struct ImageLibraryMigrationTests {
    static func fixture(_ scratch: Scratch, path: String = "old/image.png") throws -> Data {
        let generated = try GenerationRecord.embedded(in: LibraryAnnotationTests.image(seed: 101))
        let data = try PNGTextChunks.inserting([
            (GenerationRecord.referenceKeyword, Data("reference".utf8).base64EncodedString()),
            ("zephra:library", "{\"isFavourite\":true,\"tags\":[\"test\"]}")
        ], into: generated)
        try data.write(to: scratch.make(path))
        return data
    }

    @Test("owned images and metadata move byte for byte; unrelated files stay")
    func ownedFiles() throws {
        let scratch = Scratch("ImageMigration")
        let generated = try Self.fixture(scratch)
        let source = SourceRecord(importedAt: Date(), originalFileName: "reference.jpg",
                                  width: 1, height: 1, digest: "abc")
        let imported = try PNGTextChunks.inserting([source.entry()], into: MockBackend.pngData)
        try imported.write(to: scratch.make("old/Sources/reference.png"))
        try imported.write(to: scratch.make("old/Recently Deleted/trashed.png"))
        try scratch.write("albums", to: "old/\(AlbumManifest.fileName)")
        try scratch.write("trash", to: "old/Recently Deleted/\(RecentlyDeletedManifest.fileName)")
        for path in ["old/foreign.png", "old/Sources/foreign.png", "old/Recently Deleted/foreign.png"] {
            try MockBackend.pngData.write(to: scratch.make(path))
        }
        let move = ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("new"))
        #expect(try move.run().isEmpty)
        #expect(try Data(contentsOf: scratch.url("new/image.png")) == generated)
        #expect(try Data(contentsOf: scratch.url("new/Sources/reference.png")) == imported)
        #expect(try Data(contentsOf: scratch.url("new/Recently Deleted/trashed.png")) == imported)
        #expect(scratch.hasFile("new/\(AlbumManifest.fileName)"))
        #expect(scratch.hasFile("new/Recently Deleted/\(RecentlyDeletedManifest.fileName)"))
        #expect(!scratch.hasFile("old/image.png"))
        #expect(!scratch.hasFile("old/Sources/reference.png"))
        #expect(scratch.hasFile("old/foreign.png"))
        #expect(scratch.hasFile("old/Sources/foreign.png"))
        #expect(scratch.hasFile("old/Recently Deleted/foreign.png"))
    }

    @Test("conflicting image or manifest keeps both libraries")
    func conflicts() throws {
        for path in ["image.png", AlbumManifest.fileName] {
            let scratch = Scratch("ImageConflict")
            _ = try Self.fixture(scratch)
            try scratch.write("old", to: "old/\(AlbumManifest.fileName)")
            try scratch.write("new", to: "new/\(path)")
            #expect(throws: ImageDirectoryError.self) {
                try ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("new")).run()
            }
            #expect(scratch.hasFile("old/image.png"))
            #expect(try String(contentsOf: scratch.url("new/\(path)"), encoding: .utf8) == "new")
        }
    }

    @Test("nested roots, aliases, linked files and linked collection folders are refused")
    func unsafePaths() throws {
        let scratch = Scratch("ImagePaths")
        _ = try Self.fixture(scratch)
        for target in [scratch.url("old"), scratch.url("old/nested"), scratch.root] {
            #expect(throws: ImageDirectoryError.self) {
                try ImageLibraryMigration(from: scratch.url("old"), to: target).run()
            }
        }
        try scratch.link("alias", to: scratch.url("old").path)
        #expect(throws: ImageDirectoryError.self) {
            try ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("alias")).run()
        }
        try scratch.link("old/linked.png", to: scratch.url("old/image.png").path)
        #expect(throws: ImageDirectoryError.self) {
            try ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("new")).run()
        }
        try FileManager.default.removeItem(at: scratch.url("old/linked.png"))
        try scratch.link("old/Sources", to: scratch.url("outside").path)
        #expect(throws: ImageDirectoryError.self) {
            try ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("new")).run()
        }
    }

    @Test("missing disk, a file destination and insufficient free space fail safely")
    func unavailableDestination() throws {
        let scratch = Scratch("ImageAccess")
        _ = try Self.fixture(scratch)
        try scratch.write("keep", to: "file")
        #expect(throws: ImageDirectoryError.self) { try ImageDirectoryAccess.prepare(scratch.url("file")) }
        #expect(throws: ImageDirectoryError.self) {
            try ImageDirectoryAccess.requireMountedVolume(containing: URL(filePath: "/Volumes/Absent/Images"), mounted: [])
        }
        #expect(throws: ImageDirectoryError.self) {
            try ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("new")).run(availableBytes: 0)
        }
        #expect(scratch.hasFile("old/image.png"))
    }
}
