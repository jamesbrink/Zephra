import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// A clip is its poster PNG, indexed as any picture is, with the MP4 beside it under the same
/// stem; every move of the one takes the other.
@Suite("clips in the library")
struct ImageLibraryVideoTests {
    private let library = ImageLibrary(
        root: URL(filePath: NSTemporaryDirectory())
            .appending(path: "ZephraVideoTests-\(UUID().uuidString)", directoryHint: .isDirectory))

    private func clip(seed: UInt64 = 1, createdAt: Date = Date(timeIntervalSince1970: 1_772_000_000))
        -> GeneratedImage
    {
        var settings = GenerationSettings.defaults(for: ModelCatalog.ltx2Distilled4bit)
        settings.prompt = "a kite over a beach"
        settings.seed = seed
        return GeneratedImage(
            pngData: MockBackend.pngData, settings: settings,
            modelID: ModelCatalog.ltx2Distilled4bit.id, createdAt: createdAt, duration: .seconds(9),
            video: GeneratedVideo(
                poster: MockBackend.pngData, mp4: Data([0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70]),
                frameCount: 49, frameRate: 24))
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test("a clip is written as its poster with the MP4 beside it, and the record says how long")
    func writesThePair() throws {
        defer { try? FileManager.default.removeItem(at: library.root) }
        let url = try library.write(clip())
        let sidecar = VideoSidecar.url(beside: url)
        #expect(sidecar.lastPathComponent == url.deletingPathExtension().lastPathComponent + ".mp4")
        #expect(exists(sidecar))
        let record = try #require(GenerationRecord.read(from: try Data(contentsOf: url)))
        #expect(record.isVideo)
        #expect(record.frameCount == 49)
        #expect(record.frameRate == 24)
        #expect(record.settings().frames == 49)
        let items = LibraryScan(library: library).rescan()
        #expect(items.count == 1, "the MP4 is not listed; the poster is")
        #expect(items.first?.isVideo == true)
        #expect(items.first?.videoURL == sidecar)
        #expect(items.first?.videoSeconds.map { abs($0 - 49.0 / 24) < 1e-9 } == true)
    }

    @Test("a picture has no sidecar and says so")
    func picturesHaveNone() throws {
        defer { try? FileManager.default.removeItem(at: library.root) }
        var settings = GenerationSettings.defaults(for: ModelCatalog.default)
        settings.prompt = "x"
        let url = try library.write(
            GeneratedImage(pngData: MockBackend.pngData, settings: settings, modelID: "m", duration: .seconds(1)))
        #expect(VideoSidecar.existing(beside: url) == nil)
        let item = try #require(LibraryScan(library: library).rescan().first)
        #expect(!item.isVideo && item.videoURL == nil && item.videoSeconds == nil)
        #expect(GenerationRecord.read(from: try Data(contentsOf: url))?.frameCount == nil)
    }

    @Test("a second clip with the same name steps both files around the first")
    func stepsAroundBothFiles() throws {
        defer { try? FileManager.default.removeItem(at: library.root) }
        let first = try library.write(clip())
        let second = try library.write(clip())
        #expect(second.lastPathComponent.hasSuffix("-2.png"))
        #expect(exists(VideoSidecar.url(beside: first)) && exists(VideoSidecar.url(beside: second)))
    }

    @Test("deleting moves the pair to Recently Deleted and Put Back brings both home, renamed together")
    func deleteAndPutBack() throws {
        defer { try? FileManager.default.removeItem(at: library.root) }
        let url = try library.write(clip())
        let deleted = try library.moveToRecentlyDeleted(url)
        #expect(!exists(url) && !exists(VideoSidecar.url(beside: url)))
        #expect(exists(deleted) && exists(VideoSidecar.url(beside: deleted)))
        // Something else took the name meanwhile, so Put Back lands both files under a new one.
        let squatter = try library.write(clip())
        #expect(squatter.lastPathComponent == url.lastPathComponent)
        let restored = try library.restoreFromRecentlyDeleted(deleted)
        #expect(restored.lastPathComponent.hasSuffix("-2.png"))
        #expect(exists(restored) && exists(VideoSidecar.url(beside: restored)))
        #expect(!exists(deleted) && !exists(VideoSidecar.url(beside: deleted)))
        #expect(LibraryScan(library: library).rescan().count == 2)
    }

    @Test("discarding removes the clip with its poster")
    func discardRemovesBoth() throws {
        defer { try? FileManager.default.removeItem(at: library.root) }
        let url = try library.write(clip())
        try library.discard(url)
        #expect(!exists(url) && !exists(VideoSidecar.url(beside: url)))
    }

    @Test("a picture beside somebody else's same-stem MP4 leaves it alone when deleted")
    func unrelatedSidecarIsLeftAlone() throws {
        defer { try? FileManager.default.removeItem(at: library.root) }
        var settings = GenerationSettings.defaults(for: ModelCatalog.default)
        settings.prompt = "x"
        let picture = try library.write(
            GeneratedImage(pngData: MockBackend.pngData, settings: settings, modelID: "m", duration: .seconds(1)))
        let stranger = VideoSidecar.url(beside: picture)
        try Data([1, 2, 3]).write(to: stranger)
        #expect(VideoSidecar.existing(beside: picture) == nil, "a picture's record says it has no clip")
        try library.moveToRecentlyDeleted(picture)
        #expect(exists(stranger), "the stranger's file stays where it was")
        // And no picture is ever written onto a stem whose MP4 is taken.
        let next = try library.write(
            GeneratedImage(pngData: MockBackend.pngData, settings: settings, modelID: "m", duration: .seconds(1)))
        #expect(next.lastPathComponent != picture.lastPathComponent)
    }

    @Test("a Put Back whose poster cannot move puts the clip back beside it")
    func failedRestoreRollsTheClipBack() throws {
        defer { try? FileManager.default.removeItem(at: library.root) }
        let url = try library.write(clip())
        let deleted = try library.moveToRecentlyDeleted(url)
        // A dangling link squats on the poster's name at home: `availableURL` does not see it
        // (the link's target is not there), the clip moves first, and the poster's move fails.
        try FileManager.default.createSymbolicLink(
            at: url, withDestinationURL: library.root.appending(path: "nowhere.png"))
        #expect(throws: (any Error).self) { try library.restoreFromRecentlyDeleted(deleted) }
        #expect(exists(deleted) && exists(VideoSidecar.url(beside: deleted)), "the pair is still together in Recently Deleted")
        #expect(!exists(VideoSidecar.url(beside: url)), "no clip is left beside the squatter")
    }

    @Test("moving the library takes the clip along")
    func migrationCarriesTheSidecar() throws {
        defer { try? FileManager.default.removeItem(at: library.root) }
        let destination = URL(filePath: NSTemporaryDirectory())
            .appending(path: "ZephraVideoTests-dest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }
        let url = try library.write(clip())
        let files = try ImageLibraryMigration(from: library.root, to: destination).inventory()
        #expect(files.map(\.path).sorted() == [url.lastPathComponent, VideoSidecar.url(beside: url).lastPathComponent].sorted())
    }
}
