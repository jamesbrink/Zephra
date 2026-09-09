import SwiftUI

/// The mark on the card of the model this Mac would be started on.
///
/// Drawn the way `UpscaleBadge` and `VideoBadge` are, light on a translucent dark ground,
/// because it sits on a picture and has to read over whatever that picture happens to be. It
/// is on the picture rather than beside the name so the name keeps the whole of its line: a
/// chip there truncated "Z-Image Turbo · 8-bit" to "Z-Image Turbo…".
struct RecommendedBadge: View {
    var body: some View {
        Text("Recommended")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(ZephraChrome.badgeForeground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(ZephraChrome.badgeBackdrop, in: Capsule())
            .padding(6)
    }
}

#Preview("Recommended") {
    RecommendedBadge()
        .padding(20)
        .background(Color.canvasBackground)
}
