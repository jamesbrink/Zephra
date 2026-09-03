import SwiftUI

/// The place a seed will take once it has been rendered: a dashed square the same size as the
/// thumbnail that will replace it, so the strip does not grow as the run proceeds.
///
/// The three dots do not animate. A spinner here would promise progress this square has none
/// of — the one that is actually being worked on is the amber card in the sidebar, and its
/// step segments are the real measurement.
struct PendingThumbnail: View {
    var body: some View {
        RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous)
            .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(width: 72, height: 72)
            .overlay {
                HStack(spacing: 3) {
                    Circle().fill(Color.safelight)
                    Circle().fill(.tertiary)
                    Circle().fill(.tertiary)
                }
                .frame(width: 18, height: 4)
            }
            .accessibilityLabel("A seed still to come")
    }
}

#Preview("Pending") {
    HStack(spacing: 8) {
        PendingThumbnail()
        PendingThumbnail()
    }
    .padding()
    .background(Color.canvasBackground)
}
