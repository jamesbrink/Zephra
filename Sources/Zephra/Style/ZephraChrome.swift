import SwiftUI

/// The measurements every panel, chip, card, and thumbnail in the app is drawn from.
///
/// One place for them so a corner radius means the same thing wherever it appears: the prompt
/// capsule and a sidebar card that look related actually are related, and changing the family
/// resemblance is one edit rather than a hunt for repeated numbers.
enum ZephraChrome {
    /// The floating prompt capsule, the largest radius in the app.
    static let capsuleRadius: CGFloat = 16
    /// The picture in the reference well: a step above a card, since it sits on the capsule.
    static let wellRadius: CGFloat = 10
    /// A small card in a list: a queue row, a block of facts.
    static let cardRadius: CGFloat = 8
    /// A square image standing in for a bigger one.
    static let thumbnailRadius: CGFloat = 8
    /// A small square on the sidebar's wall: a step under the cards above it, so a card reads
    /// as a thing to act on and a square as a thing to look at.
    static let tileRadius: CGFloat = 5
    /// Half the height of a 22 pt chip, which is what makes it a capsule.
    static let chipRadius: CGFloat = 11

    /// The one-pixel line that separates a surface from what is behind it. The system's own
    /// separator, so it is right in both appearances without a second definition.
    static let hairline = Color(nsColor: .separatorColor)

    /// The height of one row in the sidebar's source lists.
    static let sidebarRowHeight: CGFloat = 28

    /// How far the floating capsule's shadow spreads.
    static let shadowRadius: CGFloat = 22
    /// How far below the capsule that shadow falls.
    static let shadowY: CGFloat = 8
    /// How dark it is: enough to lift the capsule off a bright picture, not enough to smudge it.
    static let shadowOpacity: Double = 0.28
}
