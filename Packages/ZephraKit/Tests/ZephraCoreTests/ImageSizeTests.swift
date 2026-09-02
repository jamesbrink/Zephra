import Testing

@testable import ZephraCore

@Suite("ImageSize")
struct ImageSizeTests {
    @Test("aligned(to:) rounds each dimension up to the nearest multiple")
    func alignsUpward() {
        let aligned = ImageSize(width: 1020, height: 761).aligned(to: 16)
        #expect(aligned == ImageSize(width: 1024, height: 768))
    }

    @Test("aligned(to:) rounds each dimension down to the nearest multiple")
    func alignsDownward() {
        let aligned = ImageSize(width: 1030, height: 1000).aligned(to: 16)
        #expect(aligned == ImageSize(width: 1024, height: 1008))
    }

    @Test("aligned(to:) never returns a dimension below the alignment")
    func neverBelowAlignment() {
        let aligned = ImageSize(width: 3, height: 0).aligned(to: 16)
        #expect(aligned == ImageSize(width: 16, height: 16))
    }

    @Test("aligned(to:) leaves an already aligned size untouched")
    func leavesAlignedSizeAlone() {
        let size = ImageSize(width: 1216, height: 832)
        #expect(size.aligned(to: 16) == size)
    }

    @Test("label uses a multiplication sign between the dimensions")
    func labelFormatting() {
        let size = ImageSize(width: 1024, height: 1024)
        #expect(size.label == "1024 × 1024")
        #expect(size.description == size.label)
    }

    @Test("aspectRatio and pixelCount describe the size")
    func derivedValues() {
        let size = ImageSize(width: 1024, height: 512)
        #expect(size.aspectRatio == 2)
        #expect(size.pixelCount == 524_288)
    }
}
