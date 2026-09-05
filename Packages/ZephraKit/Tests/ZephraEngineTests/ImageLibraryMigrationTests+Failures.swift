import Foundation
import Testing
import ZephraTestSupport

@testable import ZephraEngine

extension ImageLibraryMigrationTests {
    @Test("copy failure and corrupted copy preserve every original")
    func copyFailures() throws {
        for corrupt in [false, true] {
            let scratch = Scratch("ImageCopy")
            _ = try Self.fixture(scratch)
            let move = ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("new"))
            #expect(throws: (any Error).self) {
                try move.run(copy: { _, target in
                    if corrupt { try Data("corrupt".utf8).write(to: target) }
                    else { throw ImageDirectoryError("copy failed") }
                })
            }
            #expect(scratch.hasFile("old/image.png"))
            #expect(!scratch.hasFile("new/image.png"))
        }
    }

    @Test("partial publication rolls back verified copies without removing originals")
    func publishFailure() throws {
        let scratch = Scratch("ImagePublish")
        _ = try Self.fixture(scratch, path: "old/a.png")
        _ = try Self.fixture(scratch, path: "old/b.png")
        let move = ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("new"))
        #expect(throws: ImageDirectoryError.self) {
            try move.run(publish: { from, to in
                if to.lastPathComponent == "b.png" { throw ImageDirectoryError("publish failed") }
                try FileManager.default.moveItem(at: from, to: to)
            })
        }
        #expect(scratch.hasFile("old/a.png"))
        #expect(scratch.hasFile("old/b.png"))
        #expect(!scratch.hasFile("new/a.png"))
        #expect(!scratch.hasFile("new/b.png"))
    }

    @Test("changed originals survive cleanup and the complete destination is retained")
    func changedOriginal() throws {
        let scratch = Scratch("ImageChanged")
        let bytes = try Self.fixture(scratch)
        let move = ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("new"))
        let warnings = try move.run(publish: { from, to in
            try FileManager.default.moveItem(at: from, to: to)
            try Data("changed".utf8).write(to: scratch.url("old/image.png"))
        })
        #expect(warnings.count == 1)
        #expect(try Data(contentsOf: scratch.url("new/image.png")) == bytes)
        #expect(try String(contentsOf: scratch.url("old/image.png"), encoding: .utf8) == "changed")
    }

    @Test("cleanup failure returns warnings after complete publication")
    func cleanupFailure() throws {
        let scratch = Scratch("ImageCleanup")
        _ = try Self.fixture(scratch)
        let warnings = try ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("new"))
            .run(removeSource: { _ in throw ImageDirectoryError("cleanup failed") })
        #expect(warnings.count == 1)
        #expect(scratch.hasFile("old/image.png"))
        #expect(scratch.hasFile("new/image.png"))
    }

    @Test("a changed published copy is retained and reported on rollback")
    func retainedPublication() throws {
        let scratch = Scratch("ImageRetained")
        _ = try Self.fixture(scratch, path: "old/a.png")
        _ = try Self.fixture(scratch, path: "old/b.png")
        do {
            _ = try ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("new"))
                .run(publish: { from, to in
                    if to.lastPathComponent == "b.png" {
                        try Data("changed".utf8).write(to: scratch.url("new/a.png"))
                        throw ImageDirectoryError("publish failed")
                    }
                    try FileManager.default.moveItem(at: from, to: to)
                })
            Issue.record("Publication should fail")
        } catch {
            #expect(error.localizedDescription.contains("Copies retained at:"))
        }
        #expect(scratch.hasFile("old/a.png"))
        #expect(scratch.hasFile("old/b.png"))
        #expect(scratch.hasFile("new/a.png"))
    }
}

extension ImageLibraryMigrationTests {
    @Test("destination-only album and trash metadata cannot relabel incoming images")
    func destinationOnlyMetadata() throws {
        for path in [AlbumManifest.fileName, "Recently Deleted/" + RecentlyDeletedManifest.fileName] {
            let scratch = Scratch("ImageDestinationMetadata")
            _ = try Self.fixture(scratch)
            try scratch.write("existing", to: "new/\(path)")
            #expect(throws: ImageDirectoryError.self) {
                try ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("new")).run()
            }
            #expect(scratch.hasFile("old/image.png"))
            #expect(!scratch.hasFile("new/image.png"))
        }
    }

    @Test("a disconnected source disk is not treated as an empty library")
    func disconnectedSource() throws {
        let scratch = Scratch("ImageMissingSource")
        let missing = URL(filePath: "/Volumes/Zephra-absent-\(UUID().uuidString)/Images")
        #expect(throws: ImageDirectoryError.self) {
            try ImageLibraryMigration(from: missing, to: scratch.url("new")).run()
        }
        #expect(!scratch.hasFile("new"))
    }

    @Test("a nonregular PNG is refused without attempting a read")
    func nonregularImage() throws {
        let scratch = Scratch("ImageSpecial")
        try scratch.make("old/folder.png", isDirectory: true)
        #expect(throws: ImageDirectoryError.self) {
            try ImageLibraryMigration(from: scratch.url("old"), to: scratch.url("new")).run()
        }
        #expect(scratch.hasFile("old/folder.png"))
    }

    @Test("a read-only destination cannot be selected")
    func unwritableDestination() throws {
        let scratch = Scratch("ImageReadOnly")
        let folder = try scratch.make("read-only", isDirectory: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        #expect(throws: ImageDirectoryError.self) { try ImageDirectoryAccess.prepare(folder) }
    }
}
