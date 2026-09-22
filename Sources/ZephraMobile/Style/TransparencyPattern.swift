import SwiftUI
import UIKit
import ZephraCore
import ZephraStyle

/// `TransparencyGround`'s checkerboard as a `UIColor`, for the one place on this phone that
/// draws in UIKit rather than in SwiftUI.
///
/// The viewer's page is a `UIScrollView` whose image view is sized to the picture's fitted
/// rectangle and zooms with it, so the ground has to be that view's own background: a SwiftUI
/// ground behind the scroll view would checker the whole screen rather than the picture.
///
/// A dynamic colour, so the pattern is redrawn when the appearance changes; the two squares
/// and their parity are `Checkerboard`'s, the same rule the SwiftUI ground draws and the Mac
/// bakes into every JPEG.
enum TransparencyPattern {
    /// The checkerboard, tiled by UIKit across whatever it is set on.
    static func color() -> UIColor {
        UIColor { traits in
            let cell = CGFloat(Checkerboard.cell)
            let renderer = UIGraphicsImageRenderer(
                size: CGSize(width: cell * 2, height: cell * 2))
            let tile = renderer.image { context in
                for row in 0..<2 {
                    for column in 0..<2 {
                        let light = Checkerboard.isLight(
                            x: column * Checkerboard.cell, y: row * Checkerboard.cell)
                        let colour = light ? Color.transparencyLight : Color.transparencyDark
                        UIColor(colour).resolvedColor(with: traits).setFill()
                        context.fill(
                            CGRect(
                                x: CGFloat(column) * cell, y: CGFloat(row) * cell,
                                width: cell, height: cell))
                    }
                }
            }
            return UIColor(patternImage: tile)
        }
    }
}
