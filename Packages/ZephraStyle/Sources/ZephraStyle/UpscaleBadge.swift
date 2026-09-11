import SwiftUI

/// A small "×4" in the corner of a thumbnail, so a picture that was made larger from another
/// says so before it is selected: an upscale looks exactly like its parent at thumbnail size,
/// and without this the two are told apart only by the inspector.
///
/// Dark on a translucent ground rather than a chip, because it sits on a picture rather than
/// on the chrome, and the favourite's star in the opposite corner sets the register.
public struct UpscaleBadge: View {
    /// How many times larger than its parent the picture is.
    public let factor: Int

    /// A badge for a picture `factor` times its parent.
    public init(factor: Int) {
        self.factor = factor
    }

    public var body: some View {
        Text("\u{00D7}\(factor)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(6)
            .accessibilityLabel("Upscaled \(factor) times")
    }
}

#Preview("Badges") {
    HStack(spacing: 12) {
        UpscaleBadge(factor: 2)
        UpscaleBadge(factor: 4)
    }
    .padding(24)
    .background(.gray)
}
