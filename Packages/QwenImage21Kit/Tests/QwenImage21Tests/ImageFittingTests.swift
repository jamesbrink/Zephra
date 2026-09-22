import Foundation
import Testing

@testable import QwenImage21

@Suite("A size is rounded when it is derived and floored when it is handed in")
struct ImageFittingTests {
    @Test("a square reference at the default resolution gives the default square")
    func squareIsTheResolution() {
        let target = QwenImage21ImageFitting.dimensions(ratio: 1)
        #expect(target == .init(width: 1024, height: 1024))
    }

    @Test("the aspect follows the reference at about a megapixel, both edges on the grid")
    func aspectFollowsTheReference() {
        for (width, height) in [(1920, 1080), (1080, 1920), (3, 2), (4, 5)] {
            let ratio = QwenImage21ImageFitting.ratio(width: width, height: height)
            let target = QwenImage21ImageFitting.dimensions(ratio: ratio)
            #expect(target.width.isMultiple(of: 32))
            #expect(target.height.isMultiple(of: 32))
            let area = Double(target.width * target.height)
            #expect(area > 0.8 * 1024 * 1024 && area < 1.25 * 1024 * 1024)
            let fitted = Double(target.width) / Double(target.height)
            #expect(abs(fitted - ratio) < 0.06, "the shape is kept to within a grid step")
        }
    }

    @Test("dimensions rounds to the nearest multiple, which can grow an edge")
    func dimensionsRound() {
        // 16:9 at a megapixel is 1365.3 by 768; the width rounds up to 1376, not down to 1344.
        let target = QwenImage21ImageFitting.dimensions(ratio: 16.0 / 9.0)
        #expect(target == .init(width: 1376, height: 768))
    }

    @Test("a size handed in is floored, never grown")
    func trimFloors() {
        #expect(QwenImage21ImageFitting.trimmed(width: 1375, height: 769) == .init(width: 1344, height: 768))
        #expect(QwenImage21ImageFitting.trimmed(width: 1024, height: 1024) == .init(width: 1024, height: 1024))
    }

    @Test("a picture smaller than one cell still comes back as one cell")
    func tinyPictures() {
        #expect(QwenImage21ImageFitting.trimmed(width: 7, height: 1) == .init(width: 32, height: 32))
        let target = QwenImage21ImageFitting.dimensions(targetArea: 16, ratio: 1)
        #expect(target == .init(width: 32, height: 32))
    }
}
