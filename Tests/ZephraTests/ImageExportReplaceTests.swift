import Foundation
import Testing
import ZephraTestSupport

@testable import Zephra

@Suite("Copying a file where another may already be")
struct ImageExportReplaceTests {
    @Test("a symlink and a hard link are the same file; a byte-identical copy is not")
    func linksAreTheSameFileAndCopiesAreNot() throws {
        let scratch = Scratch()
        let original = try scratch.write("pixels", to: "a.png")
        let symlink = try scratch.link("link.png", to: "a.png")
        let hardLink = scratch.url("hard.png")
        try FileManager.default.linkItem(at: original, to: hardLink)
        let twin = try scratch.write("pixels", to: "twin.png")

        #expect(ImageExport.isSameFile(original, original))
        #expect(ImageExport.isSameFile(original, symlink))
        #expect(ImageExport.isSameFile(original, hardLink))
        #expect(!ImageExport.isSameFile(original, twin))
    }

    @Test("copying onto an existing file replaces it and leaves the source untouched")
    func replacingKeepsTheSourceAndReplacesTheDestination() throws {
        let scratch = Scratch()
        let source = try scratch.write("new", to: "library/a.png")
        let destination = try scratch.write("old", to: "exports/a.png")

        try ImageExport.copyReplacing(source, to: destination)

        #expect(try String(contentsOf: source, encoding: .utf8) == "new")
        #expect(try String(contentsOf: destination, encoding: .utf8) == "new")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: scratch.url("exports").path(percentEncoded: false))
        #expect(leftovers == ["a.png"], "no staging file is left beside the result")
    }

    @Test("copying to a free name creates the file")
    func copyingToAFreeNameCreatesIt() throws {
        let scratch = Scratch()
        let source = try scratch.write("new", to: "library/a.png")
        try scratch.make("exports", isDirectory: true)
        let destination = scratch.url("exports/a.png")

        try ImageExport.copyReplacing(source, to: destination)

        #expect(try String(contentsOf: destination, encoding: .utf8) == "new")
        #expect(try String(contentsOf: source, encoding: .utf8) == "new")
    }

    @Test("a copy that cannot land leaves no staging file behind")
    func failedCopyLeavesNoStagingFile() throws {
        let scratch = Scratch()
        let source = try scratch.write("new", to: "library/a.png")
        let destination = scratch.url("missing-folder/a.png")

        #expect(throws: (any Error).self) {
            try ImageExport.copyReplacing(source, to: destination)
        }
        #expect(!scratch.hasFile("missing-folder"))
    }
}
