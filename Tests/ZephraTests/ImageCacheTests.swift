import AppKit
import Foundation
import Synchronization
import Testing
import ZephraCore

@testable import Zephra

@Suite("Session images are decoded once, off the main actor")
struct ImageCacheTests {
    /// A decoder that counts how many times it ran and takes long enough for a second request
    /// to arrive while the first is still inside it. A class, because the closure has to
    /// escape and a `Mutex` cannot be captured by one.
    private final class Tally: Sendable {
        let decodes = Mutex(0)

        var decoder: ImageCache.Decoder {
            { data, kind in
                self.decodes.withLock { $0 += 1 }
                Thread.sleep(forTimeInterval: 0.05)
                return ImageCache.decode(data, kind)
            }
        }

        var count: Int { decodes.withLock { $0 } }
    }

    @Test("two concurrent loads of one image share one decode and one object")
    func concurrentLoadsShareOneDecode() async {
        let tally = Tally()
        let cache = ImageCache(decode: tally.decoder)
        let image = PreviewImages.sample()

        async let first = cache.load(image, .full)
        async let second = cache.load(image, .full)
        let (a, b) = await (first, second)

        #expect(tally.count == 1)
        #expect(a != nil)
        #expect(a === b)
        #expect(cache.cached(image, .full) === a, "the pixels stay for the next view to ask")
    }

    @Test("the full picture and its thumbnail are two decodes, kept apart")
    func kindsAreDecodedSeparately() async {
        let tally = Tally()
        let cache = ImageCache(decode: tally.decoder)
        let image = PreviewImages.sample()

        let full = await cache.load(image, .full)
        let thumbnail = await cache.load(image, .thumbnail)

        #expect(tally.count == 2)
        #expect(full !== thumbnail)
        #expect(cache.cached(image, .thumbnail) === thumbnail)
    }

    @Test("equal reference bytes yield one object, from one decode")
    func equalReferenceBytesYieldOneObject() async {
        let tally = Tally()
        let cache = ImageCache(decode: tally.decoder)
        let png = PreviewImages.referencePNG()

        async let first = cache.referenceThumbnail(png)
        async let second = cache.referenceThumbnail(Data(png))
        let (a, b) = await (first, second)
        let again = await cache.referenceThumbnail(png)

        #expect(tally.count == 1)
        #expect(a != nil)
        #expect(a === b)
        #expect(again === a)
    }

    @Test("bytes that are not a picture decode to nothing rather than a placeholder")
    func unreadableBytesDecodeToNil() async {
        let cache = ImageCache()
        let sample = PreviewImages.sample()
        let image = GeneratedImage(
            pngData: Data("not a picture".utf8),
            settings: sample.settings,
            modelID: sample.modelID,
            duration: sample.duration)

        #expect(await cache.load(image, .full) == nil)
        #expect(cache.cached(image, .full) == nil)
    }
}
