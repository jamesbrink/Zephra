import Testing

@testable import Zephra

@Suite("The bucket a thumbnail is baked at")
struct ThumbnailSizeTests {
    @Test("a cell takes the smallest bucket that is not smaller than it")
    func smallestBucketNotSmallerThanTheCell() {
        #expect(ThumbnailSize.bucket(forWidth: 96) == .small)
        #expect(ThumbnailSize.bucket(forWidth: 128) == .small)
        #expect(ThumbnailSize.bucket(forWidth: 129) == .medium)
        #expect(ThumbnailSize.bucket(forWidth: 200) == .large)
        #expect(ThumbnailSize.bucket(forWidth: 300) == .extraLarge)
    }

    @Test("a cell wider than every bucket takes the largest rather than none")
    func widerThanEveryBucketTakesTheLargest() {
        #expect(ThumbnailSize.bucket(forWidth: 1000) == .extraLarge)
    }

    @Test("pixels are twice the points, for a Retina screen")
    func pixelsAreTwiceThePoints() {
        for size in ThumbnailSize.allCases {
            #expect(size.pixels == Int(size.points) * 2)
        }
    }

    @Test("buckets order by their edge")
    func bucketsOrderByEdge() {
        #expect(ThumbnailSize.allCases == ThumbnailSize.allCases.sorted())
        #expect(ThumbnailSize.small < ThumbnailSize.extraLarge)
    }
}
