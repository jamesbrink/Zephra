import Foundation

/// The ground a transparent picture is shown over, and the one baked into every JPEG hop.
///
/// Two greys in eight-point squares, the pattern every painting program has used for
/// transparency for thirty years. The numbers are here, in the value layer, rather than in the
/// view that draws them, because **two of the places that need this pattern cannot draw a
/// view**: a grid thumbnail and a live preview frame both cross the companion link as JPEG,
/// which has no alpha channel at all, so each composites the picture over these squares at its
/// own pixel size before it encodes. A phone then reads a transparent picture as transparent
/// with no protocol change, no mime switching, and no second idea of what transparency looks
/// like.
///
/// `TransparencyGround` (`ZephraStyle`) is the same rule drawn live, in colour sets that follow
/// the appearance. These two component bytes are the light appearance's, since what a JPEG
/// carries is fixed at the moment it is encoded and the Mac cannot know which appearance the
/// phone reading it will be in.
public enum Checkerboard {
    /// The square's edge: points on screen, pixels in a composite.
    public static let cell = 8

    /// The lighter of the two squares, as one grey component byte.
    public static let light: UInt8 = 0xFF
    /// The darker one. Far enough from the lighter square to read as a pattern, near enough
    /// that it never competes with the picture laid over it.
    public static let dark: UInt8 = 0xE0

    /// Which of the two squares covers the pixel at `x`, `y`.
    ///
    /// `cell` is a parameter so a composite at another scale can ask the same question; a cell
    /// of zero or less divides by nothing and answers light, which is a flat fill.
    public static func isLight(x: Int, y: Int, cell: Int = Self.cell) -> Bool {
        guard cell > 0 else { return true }
        let column = Int(floor(Double(x) / Double(cell)))
        let row = Int(floor(Double(y) / Double(cell)))
        return (column &+ row) % 2 == 0
    }

    /// The grey covering that pixel, which is what a compositor writes into all three channels.
    public static func component(x: Int, y: Int, cell: Int = Self.cell) -> UInt8 {
        isLight(x: x, y: y, cell: cell) ? light : dark
    }
}
