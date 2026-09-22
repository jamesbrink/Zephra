import CoreGraphics
import Testing
import ZephraCore

@testable import Zephra

/// Which well a model draws, how many tiles the strip holds, and how wide it is.
///
/// The width is the part worth pinning: the strip sits beside the prompt in one row, so "at
/// most four tiles, and past that it scrolls" is a promise about the capsule rather than a
/// number in a view.
@Suite("The reference strip's layout")
struct ReferenceStripLayoutTests {
    /// A model that reads `count` pictures, and nothing else worth saying about it.
    private func capabilities(reading count: ClosedRange<Int>, pictures: Bool = true)
        -> ModelCapabilities
    {
        ModelCapabilities(
            sizeAlignment: 16,
            sizePresets: [ImageSize(width: 1024, height: 1024)],
            sizeBounds: 512...1536,
            defaultSize: ImageSize(width: 1024, height: 1024),
            stepBounds: 1...8,
            defaultSteps: 4,
            guidanceBounds: 0...0,
            defaultGuidance: 0,
            supportsNegativePrompt: false,
            supportsSeed: true,
            supportsReferenceImage: pictures,
            referenceImageCount: count)
    }

    @Test("a model that reads one picture draws the well it always drew")
    func onePictureKeepsTheWell() {
        #expect(!ReferenceStripLayout.drawsStrip(capabilities: capabilities(reading: 1...1)))
        #expect(
            !ReferenceStripLayout.drawsStrip(
                capabilities: capabilities(reading: 1...1, pictures: false)))
    }

    @Test("a model that reads several draws the strip, even with nothing in it yet")
    func severalPicturesDrawTheStrip() {
        #expect(ReferenceStripLayout.drawsStrip(capabilities: capabilities(reading: 1...10)))
    }

    @Test("a model that reads no picture at all never draws a strip, whatever its count says")
    func noPictureNeverDrawsAStrip() {
        #expect(
            !ReferenceStripLayout.drawsStrip(
                capabilities: capabilities(reading: 1...10, pictures: false)))
    }

    @Test("the add tile is drawn while there is room and goes when the strip is full")
    func theAddTileFollowsTheRoom() {
        #expect(ReferenceStripLayout(pictures: 0, room: 10).showsAddTile)
        #expect(ReferenceStripLayout(pictures: 3, room: 7).showsAddTile)
        #expect(!ReferenceStripLayout(pictures: 10, room: 0).showsAddTile)
    }

    @Test("the row counts the pictures and the add tile together")
    func theRowCountsTheAddTile() {
        #expect(ReferenceStripLayout(pictures: 0, room: 10).tiles == 1)
        #expect(ReferenceStripLayout(pictures: 2, room: 8).tiles == 3)
        #expect(ReferenceStripLayout(pictures: 10, room: 0).tiles == 10)
    }

    @Test("an empty strip on a model with no room at all is no tiles at all")
    func nothingToDrawIsNoTiles() {
        let layout = ReferenceStripLayout(pictures: 0, room: 0)
        #expect(layout.tiles == 0)
        #expect(layout.visibleWidth == 0)
        #expect(!layout.scrolls)
    }

    @Test("four tiles fit and five scroll, and the visible width stops at four either way")
    func fourTilesAreTheWidth() {
        let four = ReferenceStripLayout(pictures: 3, room: 7)
        #expect(four.tiles == 4)
        #expect(!four.scrolls)
        #expect(four.visibleWidth == four.contentWidth)

        let ten = ReferenceStripLayout(pictures: 10, room: 0)
        #expect(ten.scrolls)
        #expect(ten.visibleWidth == four.visibleWidth)
        #expect(ten.contentWidth > ten.visibleWidth)
    }

    @Test("a width is the tiles plus the gaps between them, and nothing for no tiles")
    func widthCountsTheGaps() {
        #expect(ReferenceStripLayout.width(ofTiles: 0) == 0)
        #expect(ReferenceStripLayout.width(ofTiles: -1) == 0)
        #expect(ReferenceStripLayout.width(ofTiles: 1) == ReferenceStripLayout.tile)
        // Four 64-point tiles with three 8-point gaps between them.
        #expect(ReferenceStripLayout.width(ofTiles: 4) == CGFloat(280))
    }
}
