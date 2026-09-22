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

    /// How wide the row's own content is, laid out flat.
    var contentWidth: CGFloat { Self.width(ofTiles: tiles) }

    /// How many of them are on screen at once.
    var visibleTiles: Int { min(tiles, Self.maximumVisibleTiles) }

    /// How wide the strip is in the capsule — never more than four tiles, whatever it holds.
    var visibleWidth: CGFloat { Self.width(ofTiles: visibleTiles) }

    /// Whether there is anything off the end to scroll to.
    var scrolls: Bool { tiles > Self.maximumVisibleTiles }

    /// The width `count` tiles and the gaps between them come to.
    static func width(ofTiles count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * tile + CGFloat(count - 1) * spacing
    }
}
