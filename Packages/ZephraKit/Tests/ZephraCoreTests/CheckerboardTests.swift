import Testing
import ZephraCore

/// The one pattern a transparent picture is shown over, drawn live on screen and baked into
/// every JPEG that crosses the link.
@Suite("The transparency checkerboard's squares")
struct CheckerboardTests {
    @Test("the square at the origin is the light one, and its neighbours are not")
    func parityAtTheOrigin() {
        #expect(Checkerboard.isLight(x: 0, y: 0))
        #expect(Checkerboard.isLight(x: 7, y: 7), "still inside the first square")
        #expect(!Checkerboard.isLight(x: 8, y: 0), "one square across")
        #expect(!Checkerboard.isLight(x: 0, y: 8), "one square down")
        #expect(Checkerboard.isLight(x: 8, y: 8), "across and down is light again")
    }

    @Test("the cell size is the only thing that decides where a boundary falls")
    func theCellDecidesTheBoundary() {
        #expect(!Checkerboard.isLight(x: 1, y: 0, cell: 1))
        #expect(Checkerboard.isLight(x: 2, y: 0, cell: 1))
        #expect(Checkerboard.isLight(x: 1, y: 0, cell: 8), "the same pixel, an eight-point cell")
        #expect(Checkerboard.isLight(x: 3, y: 0, cell: 4))
        #expect(!Checkerboard.isLight(x: 4, y: 0, cell: 4))
    }

    @Test("a cell of nothing is a flat fill rather than a division by zero")
    func degenerateCell() {
        #expect(Checkerboard.isLight(x: 5, y: 9, cell: 0))
        #expect(Checkerboard.isLight(x: 5, y: 9, cell: -3))
    }

    @Test("the two greys differ, and the component follows the square")
    func theTwoGreysDiffer() {
        #expect(Checkerboard.light != Checkerboard.dark)
        #expect(Checkerboard.component(x: 0, y: 0) == Checkerboard.light)
        #expect(Checkerboard.component(x: 8, y: 0) == Checkerboard.dark)
    }
}
