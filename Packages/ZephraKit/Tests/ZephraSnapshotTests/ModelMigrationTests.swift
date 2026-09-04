import Foundation
import Testing
import ZephraCore
import ZephraTestSupport

@testable import ZephraSnapshot

@Suite("Model folder migration")
struct ModelMigrationTests {
    private let repo = "Downloads/mzbac--Z-Image-Turbo-8bit"

    @Test("downloads, partial validators, and built variants move while unrelated files stay")
    func movesOwnedDataOnly() throws {
        let scratch = Scratch("Migration")
        try scratch.write("weights", to: "old/\(repo)/model.safetensors.incomplete")
        try scratch.write("etag", to: "old/\(repo)/model.safetensors.incomplete.etag")
        try scratch.write("revision", to: "old/\(repo)/.zephra-revision")
        try scratch.write("packed", to: "old/z-image-turbo-4bit/weights.safetensors")
        try scratch.write("keep", to: "old/photographs/picture.png")
        let move = ModelMigration(from: scratch.url("old"), to: scratch.url("new"))
        #expect(try move.run().isEmpty)
        #expect(try String(contentsOf: scratch.url("new/\(repo)/model.safetensors.incomplete.etag"), encoding: .utf8) == "etag")
        #expect(scratch.hasFile("new/\(repo)/.zephra-revision"))
        #expect(scratch.hasFile("new/z-image-turbo-4bit/weights.safetensors"))
        #expect(!scratch.hasFile("old/\(repo)/model.safetensors.incomplete"))
        #expect(scratch.hasFile("old/photographs/picture.png"))
    }

    @Test("a destination conflict is refused before any source is removed")
    func collisionPreservesBoth() throws {
        let scratch = Scratch("Collision")
        try scratch.write("source", to: "old/\(repo)/weights")
        try scratch.write("destination", to: "new/\(repo)/weights")
        #expect(throws: ModelDirectoryError.self) {
            try ModelMigration(from: scratch.url("old"), to: scratch.url("new")).run()
        }
        #expect(try String(contentsOf: scratch.url("old/\(repo)/weights"), encoding: .utf8) == "source")
        #expect(try String(contentsOf: scratch.url("new/\(repo)/weights"), encoding: .utf8) == "destination")
    }

    @Test("nested roots and linked source files cannot move")
    func unsafePathsAreRefused() throws {
        let scratch = Scratch("UnsafeMigration")
        try scratch.write("keep", to: "outside/file")
        try scratch.link("old/\(repo)/weights", to: scratch.url("outside/file").path)
        for target in ["new", "old/inside", "old"] {
            #expect(throws: ModelDirectoryError.self) {
                try ModelMigration(from: scratch.url("old"), to: scratch.url(target)).run()
            }
        }
        #expect(scratch.hasFile("outside/file"))
    }

    @Test("a linked destination parent is refused without writing through it")
    func destinationLinkIsRefused() throws {
        let scratch = Scratch("LinkedDestination")
        try scratch.write("source", to: "old/\(repo)/weights")
        try scratch.make("outside", isDirectory: true)
        try scratch.link("new/Downloads", to: scratch.url("outside").path)
        #expect(throws: ModelDirectoryError.self) {
            try ModelMigration(from: scratch.url("old"), to: scratch.url("new")).run()
        }
        #expect(!scratch.hasFile("outside/mzbac--Z-Image-Turbo-8bit/weights"))
    }

    @Test("publication failure leaves every original intact")
    func publicationFailure() throws {
        let scratch = Scratch("PublishFailure")
        try scratch.write("source", to: "old/\(repo)/weights")
        let move = ModelMigration(from: scratch.url("old"), to: scratch.url("new"))
        #expect(throws: ModelDirectoryError.self) {
            try move.run(progress: { _ in }, publish: { _, _ in throw CocoaError(.fileWriteUnknown) }, removeSource: { _ in Issue.record("Source cleanup must not run") })
        }
        #expect(scratch.hasFile("old/\(repo)/weights"))
    }

    @Test("source cleanup failure reports a warning after publishing verified destination data")
    func cleanupFailure() throws {
        let scratch = Scratch("CleanupFailure")
        try scratch.write("source", to: "old/\(repo)/weights")
        let move = ModelMigration(from: scratch.url("old"), to: scratch.url("new"))
        let warnings = try move.run(progress: { _ in }, publish: FileManager.default.moveItem,
                                    removeSource: { _ in throw CocoaError(.fileWriteNoPermission) })
        #expect(warnings.count == 1)
        #expect(scratch.hasFile("new/\(repo)/weights"))
        #expect(scratch.hasFile("old/\(repo)/weights"))
    }

    @Test("verification detects same-size corruption")
    func byteVerification() throws {
        let scratch = Scratch("Verification")
        try scratch.write("abcd", to: "old/weights")
        let tree = try ModelFileTree(scratch.url("old"))
        try tree.copy(to: scratch.url("new"))
        try scratch.write("abce", to: "new/weights")
        #expect(throws: ModelDirectoryError.self) { try tree.verify(at: scratch.url("new")) }
        #expect(scratch.hasFile("old/weights"))
    }
}
