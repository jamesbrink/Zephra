import SwiftUI
import ZephraCore

/// A small play glyph with the clip's length in the corner of a thumbnail, so a clip says so
/// before it is selected: at thumbnail size its poster looks exactly like a picture.
///
/// Drawn the way `UpscaleBadge` is, dark on a translucent ground, and in the same corner: a
/// picture is one or the other, never both.
public struct VideoBadge: View {
    /// How long the clip plays, in seconds.
    public let seconds: Double

    /// A badge for a clip `seconds` long.
    public init(seconds: Double) {
        self.seconds = seconds
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.fill").font(.system(size: 8, weight: .semibold))
            Text(label).monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(6)
        // Ignoring the children rather than only labelling the stack: a label on a container
        // leaves its children in the tree, so the glyph and the duration were announced again
        // after it — "Clip, 2.0 s, Clip, 2.0 s" wherever a badge sits inside a larger element.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Clip, \(label)")
    }

    /// "2 s", or "1.5 s" when the seconds are not whole.
    private var label: String { DurationLabel.text(seconds: seconds, fraction: true) }
}

#Preview("Badges") {
    HStack(spacing: 12) {
        VideoBadge(seconds: 2)
        VideoBadge(seconds: 5.04)
    }
    .padding(24)
    .background(.gray)
}
