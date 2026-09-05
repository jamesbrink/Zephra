import Testing

@testable import Zephra

@Suite("How many cells an adaptive grid fits across")
struct GridColumnsTests {
    @Test("the count is what fits inside the inset, each cell costing an edge and a gap")
    func countsWhatFits() {
        // 900 wide, 20 in from each side: 860 usable, and the last gap is given back.
        #expect(GridColumns.count(width: 900, edge: 168, spacing: 12, inset: 20) == 4)
        #expect(GridColumns.count(width: 640, edge: 120, spacing: 10, inset: 12) == 4)
    }

    @Test("a row that fits exactly counts every cell, and one point less loses one")
    func exactFit() {
        // Four cells of 168 and three gaps of 12 are 708; plus the two insets is 748.
        #expect(GridColumns.count(width: 748, edge: 168, spacing: 12, inset: 20) == 4)
        #expect(GridColumns.count(width: 747, edge: 168, spacing: 12, inset: 20) == 3)
    }

    @Test("a pane narrower than one cell still lays one per row")
    func neverFewerThanOne() {
        #expect(GridColumns.count(width: 100, edge: 168, spacing: 12, inset: 20) == 1)
        #expect(GridColumns.count(width: 0, edge: 168, spacing: 12, inset: 20) == 1)
    }
}
