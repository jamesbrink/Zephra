import Foundation

/// The four sizes a library thumbnail is ever baked at.
///
/// Buckets rather than the slider's exact width, because the slider is continuous and the cache
/// is not: a thumbnail baked for every point between 96 and 320 would be two hundred files per
/// image and a fresh decode on every drag. Four covers the range with the largest never more
/// than a third bigger than the cell it fills, which is close enough that nobody looking at a
/// picture can tell.
nonisolated enum ThumbnailSize: Int, CaseIterable, Comparable, Sendable {
    /// The smallest cells, and the sidebar's Today grid.
    case small = 128
    /// The default the library opens at.
    case medium = 192
    /// A wide window turned up.
    case large = 288
    /// The inspector's single image, which is bigger than any cell.
    case extraLarge = 400

    /// The bucket's edge in points, which is what it is named for.
    var points: CGFloat { CGFloat(rawValue) }

    /// The edge Image I/O is asked for: twice the points, so a Retina screen has real pixels
    /// rather than a smooth guess at them.
    var pixels: Int { rawValue * 2 }

    /// The bucket to bake at for a cell of `width` points: the smallest one that is not
    /// smaller than the cell, so a thumbnail is never scaled up.
    static func bucket(forWidth width: CGFloat) -> ThumbnailSize {
        allCases.first { $0.points >= width } ?? .extraLarge
    }

    /// The next bucket up, or nil at the top. What ⌘+ steps through.
    var larger: ThumbnailSize? {
        Self.allCases.first { $0 > self }
    }

    /// The next bucket down, or nil at the bottom. What ⌘− steps through.
    var smaller: ThumbnailSize? {
        Self.allCases.last { $0 < self }
    }

    static func < (lhs: ThumbnailSize, rhs: ThumbnailSize) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
