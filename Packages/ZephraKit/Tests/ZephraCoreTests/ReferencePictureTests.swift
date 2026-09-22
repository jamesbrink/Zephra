import Foundation
import Testing

@testable import ZephraCore

@Suite("A reference picture, and what a strip of them may come to")
struct ReferencePictureTests {
    @Test("a picture is its bytes, its origin and its shape, and two alike are equal")
    func equality() {
        let one = ReferencePicture(data: Data([1, 2, 3]))
        #expect(one.origin == nil, "a drop knows no file name")
        #expect(one.size == nil, "and nobody measured it")
        #expect(one == ReferencePicture(data: Data([1, 2, 3])))
        #expect(one != ReferencePicture(data: Data([1, 2, 3]), origin: "harbour.png"))
        #expect(
            one != ReferencePicture(data: Data([1, 2, 3]), size: ImageSize(width: 8, height: 8)))
    }

    @Test("bytes stripped for the wire leave a picture that still says what it was of")
    func strippingKeepsTheProvenance() {
        let picture = ReferencePicture(
            data: Data([1, 2, 3]), origin: "harbour.png", size: ImageSize(width: 8, height: 8))
        let stripped = picture.withoutPixels()
        #expect(picture.hasPixels)
        #expect(!stripped.hasPixels)
        #expect(stripped.origin == "harbour.png")
        #expect(stripped.size == ImageSize(width: 8, height: 8))
    }

    @Test("a picture round-trips through JSON")
    func codable() throws {
        let picture = ReferencePicture(
            data: Data([0x89, 0x50]), origin: "harbour.png", size: ImageSize(width: 4, height: 2))
        let coded = try JSONDecoder().decode(
            ReferencePicture.self, from: try JSONEncoder().encode(picture))
        #expect(coded == picture)
    }

    @Test("the budget drops pictures from the end, keeping the one chosen first")
    func budgetDropsFromTheEnd() {
        let big = ReferencePicture(
            data: Data(repeating: 0x2A, count: ReferenceLimits.maximumTotalBytes / 2 + 1),
            origin: "big.png")
        let kept = ReferenceLimits.withinBudget([big, big, big])
        #expect(kept.count == 1)
        #expect(kept.first?.origin == "big.png")
        #expect(!ReferenceLimits.fit([big, big]))
        #expect(ReferenceLimits.fit([big]))
    }

    @Test("more pictures than the limit do not fit, whatever they weigh")
    func countIsAlsoALimit() {
        let tiny = ReferencePicture(data: Data([1]))
        let strip = Array(repeating: tiny, count: ReferenceLimits.maximumPictures + 1)
        #expect(!ReferenceLimits.fit(strip))
        #expect(ReferenceLimits.fit(Array(strip.dropLast())))
        #expect(ReferenceLimits.withinBudget(strip).count == strip.count, "none of them weigh much")
    }
}
