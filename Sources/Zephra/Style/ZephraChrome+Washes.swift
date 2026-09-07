import SwiftUI

/// The colours laid over or behind things, as opposed to the colours things are.
///
/// Each is a system colour or the safelight at a named strength, so a wash means the same
/// thing wherever it appears: the amber under a run's card and under its thumbnail is the same
/// amber, and the badge over a picture is legible on any picture for the same reason everywhere.
extension ZephraChrome {
    /// The glyph of a badge sitting on a picture.
    static let badgeForeground = Color.white
    /// What sits behind that glyph, so it reads on a light picture as well as a dark one.
    static let badgeBackdrop = Color.black.opacity(0.6)

    /// A whisper of safelight behind a surface that stands for the run in flight.
    static let safelightWash = Color.safelight.opacity(0.05)
    /// Safelight strong enough to be a colour of its own: the run's thumbnail before its
    /// first frame.
    static let safelightTint = Color.safelight.opacity(0.18)
    /// What lifts a square on the sidebar's wall while the pointer is over it: the wash that
    /// says it can be pressed.
    static let hoverWash = Color.white.opacity(0.12)
    /// The fill of a panel that carries a warning.
    static let warningWash = Color.safelight.opacity(0.12)
    /// The edge of that panel.
    static let warningStroke = Color.safelight.opacity(0.28)

    /// The empty reference well's quiet fill: barely there, so it reads as a place rather than
    /// a card, against the floating capsule's own material.
    static let wellFill = Color.primary.opacity(0.06)
    /// The well's fill one step brighter, under the pointer — the same instant lift `WallSquare`
    /// gives a thumbnail, so the well reads as a thing that can be pressed or dropped onto.
    static let wellFillHovered = Color.primary.opacity(0.10)
    /// The well's fill while a drop is really in flight over it (`isTargeted`), in the accent
    /// colour rather than a neutral one, since this is the one wash that means "let go here".
    static let wellFillTargeted = Color.accentColor.opacity(0.14)
    /// The empty well's dashed hairline: quieter than `hairline`, since there is nothing yet to
    /// divide from anything. It goes solid, in the accent colour, only while a drop is in flight
    /// (`ReferencePlaceholder`, `ReferenceImageWell`'s filled state).
    static let wellDash = Color.secondary.opacity(0.5)

    /// How dark the shadow under a caption over a picture is: enough to lift the words off a
    /// bright picture, not enough to draw a box round them.
    static let captionShadowOpacity: Double = 0.55
}
