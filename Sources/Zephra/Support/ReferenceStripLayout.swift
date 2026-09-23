import CoreGraphics
import ZephraCore

/// How wide the strip of reference pictures is, how many tiles it holds, and whether it scrolls.
///
/// A value rather than arithmetic inside the view, for the reason `StepProgress` is one: the
/// capsule's width must not move as pictures are added, so the answer is "at most four tiles
/// wide, and past that it scrolls" — a rule worth pinning rather than a number worth fiddling
/// with. `ReferenceStripLayoutTests` is what holds it.
struct ReferenceStripLayout: Hashable {
    /// One tile's edge, the 64 points the single well has always been.
    static let tile: CGFloat = 64
    /// The gap between two tiles.
    static let spacing: CGFloat = 8
    /// How far a tile's remove badge sits past the tile's top and trailing edges — the 5 points
    /// `ReferenceTile` offsets it by, as the single well does.
    ///
    /// The strip is a scroll view, which clips to its bounds, and a strip framed to exactly the
    /// tiles cut the badge in half at the top and on the right. So the strip carries this much
    /// headroom above the tiles and past the last one, and every width below that is the strip's
    /// own counts it once, trailing.
    static let badgeOverhang: CGFloat = 5
    /// How many tiles are on screen at once before the strip starts scrolling.
    ///
    /// Four, because the strip sits beside the prompt in one row: ten tiles laid out flat would
    /// be 700 points of the capsule and would leave the prompt a slot at the 880-point window
    /// floor. Four is 280 points, which is a third of that floor's capsule and the same order as
    /// the toolbar's trailing group.
    static let maximumVisibleTiles = 4

    /// How many pictures are in the well.
    let pictures: Int
    /// How many more the model would read (`GenerationStore.referenceRoom`).
    let room: Int

    /// Whether the strip is what the well draws at all, rather than the single well every model
    /// before this one has. The capability alone answers it: a model that reads several draws a
    /// strip whether or not anything is in it yet, since the add tile is how the first picture
    /// gets there.
    static func drawsStrip(capabilities: ModelCapabilities) -> Bool {
        capabilities.acceptsSeveralReferences
    }

    /// Whether the `+` tile is drawn: only while the model would read another picture.
    var showsAddTile: Bool { room > 0 }

    /// How many tiles the row holds, the add tile included.
    var tiles: Int { max(0, pictures) + (showsAddTile ? 1 : 0) }

    /// How wide the row's own content is, laid out flat, the badge's headroom past the last tile
    /// included.
    var contentWidth: CGFloat { Self.stripWidth(ofTiles: tiles) }

    /// How many of them are on screen at once, with no measurement of the capsule's own room —
    /// the plain "at most four" answer `ReferenceStrip` starts from before its first layout
    /// pass lands.
    var visibleTiles: Int { visibleTiles(fitting: nil) }

    /// How wide the strip is in the capsule with no measurement — never more than four tiles,
    /// whatever it holds, and the badge's headroom past the last of them.
    var visibleWidth: CGFloat { Self.stripWidth(ofTiles: visibleTiles) }

    /// Whether there is anything off the end to scroll to, with no measurement.
    var scrolls: Bool { scrolls(fitting: nil) }

    /// How many tiles fit in `measuredWidth`, the room the capsule actually offered the strip —
    /// at least one, at most four, and never more than there are tiles to show. `nil` is "not
    /// measured yet", which answers the same as the four-tile ceiling always has. The measured
    /// width carries the badge's headroom, so that comes off before the tiles are counted.
    func visibleTiles(fitting measuredWidth: CGFloat?) -> Int {
        guard tiles > 0 else { return 0 }
        let capacity =
            measuredWidth.map { Self.visibleTileCount(fitting: $0 - Self.badgeOverhang) }
            ?? Self.maximumVisibleTiles
        return min(tiles, capacity)
    }

    /// The width that many tiles come to with the badge's headroom — the strip's own frame once
    /// it has snapped to whole tiles for `measuredWidth`.
    func visibleWidth(fitting measuredWidth: CGFloat?) -> CGFloat {
        Self.stripWidth(ofTiles: visibleTiles(fitting: measuredWidth))
    }

    /// Whether there is anything off the end of `measuredWidth` to scroll to.
    func scrolls(fitting measuredWidth: CGFloat?) -> Bool {
        visibleTiles(fitting: measuredWidth) < tiles
    }

    /// The width `count` tiles and the gaps between them come to.
    static func width(ofTiles count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * tile + CGFloat(count - 1) * spacing
    }

    /// The strip's width around `count` tiles: the tiles and their gaps, and the badge's headroom
    /// past the last one. Nothing for no tiles, since there is no badge to make room for.
    static func stripWidth(ofTiles count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return width(ofTiles: count) + badgeOverhang
    }

    /// How many whole tiles fit inside `available` points, at least one and at most
    /// `maximumVisibleTiles`.
    ///
    /// This is the rule the defect was missing: the capsule offers the strip a continuous
    /// width, not a multiple of a tile, and a strip that simply took whatever it was given
    /// showed a tile sliced in half at the trailing edge with no sign it could be scrolled to.
    /// Floored rather than rounded, so a width that falls short of a whole tile never shows a
    /// fragment of it — `(available + spacing) / (tile + spacing)` is the tile count whose
    /// tiles-and-gaps fit at or under `available`, since the strip's own width never carries a
    /// trailing gap past its last tile. At least one: a strip with no room to spare still shows
    /// its first tile rather than nothing, since a tile that cannot be reached is worse than one
    /// that clips before its neighbour.
    static func visibleTileCount(fitting available: CGFloat) -> Int {
        guard available.isFinite, available > 0 else { return 1 }
        let fitting = Int(floor((available + spacing) / (tile + spacing)))
        return min(max(fitting, 1), maximumVisibleTiles)
    }
}
