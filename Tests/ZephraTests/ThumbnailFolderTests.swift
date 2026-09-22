import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing
import UniformTypeIdentifiers
import ZephraStyle
import ZephraTestSupport

@testable import Zephra

@Suite("The thumbnail folder's bake gate and sweep")
struct ThumbnailFolderTests {
    /// How many bakes are inside the baker right now, and the most there have ever been. A
    /// class, because the baker has to escape and a `Mutex` cannot be captured by one.
    private nonisolated final class Entries: Sendable {
        let counts = Mutex((running: 0, peak: 0))

        func enter() {
            counts.withLock {
                $0.running += 1
                $0.peak = max($0.peak, $0.running)
            }
        }

        func leave() { counts.withLock { $0.running -= 1 } }
        var running: Int { counts.withLock { $0.running } }
        var peak: Int { counts.withLock { $0.peak } }
    }

    /// The key the folder files one file's thumbnail under.
    private static func key(for url: URL) throws -> ThumbnailKey {
        let facts = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return ThumbnailKey(
            path: url.standardizedFileURL.path(percentEncoded: false),
            modifiedAt: try #require(facts.contentModificationDate),
            fileSize: Int64(facts.fileSize ?? 0), pixels: 16)
    }

    /// A 16 by 16 PNG that is entirely clear, which is the case HEIC has to carry.
    private static func transparentPNG() throws -> Data {
        let edge = 16
        var bytes = [UInt8]()
        for _ in 0..<(edge * edge) { bytes.append(contentsOf: [200, 40, 90, 0]) }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(
            CGImage(
                width: edge, height: edge, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: edge * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// A one-pixel picture, so a bake has something to hand back.
    private nonisolated static func pixel() -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return context?.makeImage()
    }

    @Test("a HEIC bake keeps a transparent picture's alpha, so the cache needs no branch")
    func heicKeepsAlpha() async throws {
        let scratch = Scratch()
        let url = try scratch.make("clear.png")
        try Self.transparentPNG().write(to: url)
        let folder = ThumbnailFolder(directory: scratch.url("thumbs"))

        // Baked, written as HEIC, and then read back off the disk by the same folder: the
        // second call is the one that proves the file kept what the bake had.
        let key = try Self.key(for: url)
        _ = await folder.image(for: key, of: url, pixels: 16)
        let read = try #require(await folder.image(for: key, of: url, pixels: 16))

        #expect(read.hasTransparency, "HEIC carries the alpha channel; nothing has to become PNG")
    }

    @Test("no more than four bakes run at once, and every request is answered")
    func gateHoldsAtFourAndAnswersEveryone() async {
        let scratch = Scratch()
        let entries = Entries()
        let folder = ThumbnailFolder(directory: scratch.url("thumbs")) { _, _, _ in
            entries.enter()
            Thread.sleep(forTimeInterval: 0.05)
            entries.leave()
            return Self.pixel()
        }
        let requests = (0 ..< 12).map { index in
            (key: ThumbnailKey(path: "/p\(index).png", modifiedAt: .now, fileSize: 1, pixels: 256),
             url: scratch.url("p\(index).png"))
        }

        let answered = await withTaskGroup(of: Bool.self) { group in
            for request in requests {
                group.addTask {
                    await folder.image(for: request.key, of: request.url, pixels: 256) != nil
                }
            }
            var answered = 0
            for await answer in group where answer { answered += 1 }
            return answered
        }

        #expect(answered == 12)
        let peak = entries.peak
        #expect(peak <= 4, "the gate let \(peak) bakes run at once")
        #expect(peak >= 1)
        #expect(entries.running == 0)
    }

    @Test("the sweep removes what was last used before the cutoff and the shard it empties")
    func sweepDiscardsOldEntriesAndEmptyShards() throws {
        let scratch = Scratch()
        let old = try scratch.write("old", to: "thumbs/ab/old.heic")
        let kept = try scratch.write("new", to: "thumbs/ab/kept.heic")
        let lonely = try scratch.write("old", to: "thumbs/cd/lonely.heic")
        let cutoff = Date().addingTimeInterval(-ThumbnailFolder.keepFor)
        try Self.backdate(old, to: cutoff.addingTimeInterval(-3600))
        try Self.backdate(lonely, to: cutoff.addingTimeInterval(-3600))
        try Self.backdate(kept, to: cutoff.addingTimeInterval(3600))

        ThumbnailFolder.discardEntries(under: scratch.url("thumbs"), lastUsedBefore: cutoff)

        #expect(!scratch.hasFile("thumbs/ab/old.heic"))
        #expect(scratch.hasFile("thumbs/ab/kept.heic"))
        #expect(!scratch.hasFile("thumbs/cd/lonely.heic"))
        #expect(!scratch.hasFile("thumbs/cd"), "a shard left empty goes with its last entry")
    }

    /// Sets both dates the sweep may read, since the file system keeps the access date here.
    private static func backdate(_ file: URL, to date: Date) throws {
        var file = file
        var values = URLResourceValues()
        values.contentAccessDate = date
        values.contentModificationDate = date
        try file.setResourceValues(values)
    }
}
