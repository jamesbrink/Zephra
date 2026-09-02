import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("ImageLibrary history")
struct ImageLibraryHistoryTests {
    @Test("images written earlier come back with their settings, newest first")
    func restoreRoundTrip() throws {
        let library = ImageLibrary(root: Self.scratchDirectory())
        defer { try? FileManager.default.removeItem(at: library.root) }
        let older = Self.image(prompt: "a harbour in the rain", seed: 1, at: 1_772_000_000)
        let newer = Self.image(prompt: "a lighthouse at dusk", seed: 2, at: 1_772_000_060)
        try library.write(older)
        try library.write(newer)

        let restored = library.restore(limit: 24)
        #expect(restored.map(\.settings.prompt) == [newer, older].map(\.settings.prompt))
        #expect(restored.first?.settings == newer.settings)
        #expect(restored.first?.modelID == newer.modelID)
        #expect(restored.first?.createdAt == newer.createdAt)
        #expect(restored.first?.fileURL?.lastPathComponent.hasSuffix("-s2.png") == true)
        #expect(restored.first?.pngData.count ?? 0 > MockBackend.pngData.count, "record included")
    }

    @Test("a PNG that carries no record is ignored, and the limit still fills up")
    func foreignFilesAreSkipped() throws {
        let library = ImageLibrary(root: Self.scratchDirectory())
        defer { try? FileManager.default.removeItem(at: library.root) }
        try library.write(Self.image(prompt: "ours", seed: 1, at: 1_772_000_000))
        try FileManager.default.createDirectory(at: library.root, withIntermediateDirectories: true)
        // Written last, so it would be first if the record were not what decides.
        try MockBackend.pngData.write(to: library.root.appending(path: "someone-elses.png"))

        let restored = library.restore(limit: 24)
        #expect(restored.count == 1)
        #expect(restored.first?.settings.prompt == "ours")
        #expect(library.restore(limit: 0).isEmpty)
    }

    @Test("restore honours the limit and an empty folder restores nothing")
    func limits() throws {
        let library = ImageLibrary(root: Self.scratchDirectory())
        defer { try? FileManager.default.removeItem(at: library.root) }
        #expect(library.restore(limit: 24).isEmpty)

        for index in 0..<3 {
            try library.write(
                Self.image(prompt: "image \(index)", seed: UInt64(index), at: 1_772_000_000 + index)
            )
        }
        #expect(library.restore(limit: 2).map(\.settings.prompt) == ["image 2", "image 1"])
    }

    @Test("a discarded file leaves the folder")
    func discardRemovesTheFile() throws {
        let library = ImageLibrary(root: Self.scratchDirectory())
        defer { try? FileManager.default.removeItem(at: library.root) }
        let url = try library.write(Self.image(prompt: "a lighthouse", seed: 1, at: 1_772_000_000))

        try library.discard(url)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(library.restore(limit: 24).isEmpty)
    }

    private static func scratchDirectory() -> URL {
        URL(filePath: NSTemporaryDirectory())
            .appending(path: "ZephraLibraryHistoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private static func image(prompt: String, seed: UInt64, at time: Int) -> GeneratedImage {
        var settings = GenerationSettings.defaults(for: ModelCatalog.default)
        settings.prompt = prompt
        settings.seed = seed
        return GeneratedImage(
            pngData: MockBackend.pngData,
            settings: settings,
            modelID: ModelCatalog.default.id,
            createdAt: Date(timeIntervalSince1970: TimeInterval(time)),
            duration: .seconds(3)
        )
    }
}
