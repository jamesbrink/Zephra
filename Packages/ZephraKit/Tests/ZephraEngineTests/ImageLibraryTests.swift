import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("ImageLibrary")
struct ImageLibraryTests {
    @Test("a written file is named for its timestamp and seed")
    func fileNaming() throws {
        let library = ImageLibrary(root: Self.scratchDirectory())
        defer { try? FileManager.default.removeItem(at: library.root) }
        let stamp = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: .current, year: 2026, month: 3, day: 4,
                    hour: 5, minute: 6, second: 7
                )
            )
        )

        let url = try library.write(Self.image(seed: 42, createdAt: stamp))
        #expect(url.lastPathComponent == "zephra-20260304-050607-s42.png")
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))

        // A second image with the same second and seed gets a suffix rather than clobbering.
        let second = try library.write(Self.image(seed: 42, createdAt: stamp))
        #expect(second.lastPathComponent == "zephra-20260304-050607-s42-2.png")
    }

    @Test("a hundredth image with the same name gets a unique name rather than clobbering")
    func suffixesRunOut() throws {
        let library = ImageLibrary(root: Self.scratchDirectory())
        defer { try? FileManager.default.removeItem(at: library.root) }
        let stamp = Date(timeIntervalSince1970: 1_772_000_000)

        var names: Set<String> = []
        for _ in 0..<101 {
            let url = try library.write(Self.image(seed: 7, createdAt: stamp))
            #expect(names.insert(url.lastPathComponent).inserted, "\(url.lastPathComponent) reused")
        }
        #expect(try Self.pngCount(in: library.root) == 101)
    }

    @Test("a library whose folder was never created scans as empty")
    func missingFolderIsEmpty() {
        let library = ImageLibrary(root: Self.scratchDirectory())
        #expect(LibraryScan(library: library).rescan().isEmpty)
        #expect(LibraryScan(library: library).fingerprint() == 0)
    }

    @Test("a discarded file leaves the folder")
    func discardRemovesTheFile() throws {
        let library = ImageLibrary(root: Self.scratchDirectory())
        defer { try? FileManager.default.removeItem(at: library.root) }
        let url = try library.write(Self.image(seed: 1, createdAt: Date(timeIntervalSince1970: 1)))

        try library.discard(url)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(LibraryScan(library: library).rescan().isEmpty)
    }

    private static func scratchDirectory() -> URL {
        URL(filePath: NSTemporaryDirectory())
            .appending(path: "ZephraLibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private static func pngCount(in root: URL) throws -> Int {
        try FileManager.default
            .contentsOfDirectory(atPath: root.path(percentEncoded: false))
            .filter { $0.hasSuffix(".png") }
            .count
    }

    private static func image(seed: UInt64, createdAt: Date) -> GeneratedImage {
        var settings = GenerationSettings.defaults(for: ModelCatalog.default)
        settings.prompt = "a lighthouse"
        settings.seed = seed
        return GeneratedImage(
            pngData: MockBackend.pngData,
            settings: settings,
            modelID: ModelCatalog.default.id,
            createdAt: createdAt,
            duration: .seconds(1)
        )
    }
}
