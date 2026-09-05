import CoreGraphics
import Foundation
import Synchronization
import Testing
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

    /// A one-pixel picture, so a bake has something to hand back.
    private nonisolated static func pixel() -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return context?.makeImage()
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
