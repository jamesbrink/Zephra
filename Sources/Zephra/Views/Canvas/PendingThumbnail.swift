import SwiftUI

/// The place a seed will take once it has been rendered: a dashed square the same size as the
/// thumbnail that will replace it, so the strip does not grow as the run proceeds.
///
/// The three dots do not animate, and none of them is amber. Amber means the model is working
/// on that thing, and nothing is happening in this square: the one being worked on is the card
/// in the sidebar, whose step segments are the real measurement.
struct PendingThumbnail: View {
    var body: some View {
        RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous)
            .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(width: 72, height: 72)
            .overlay {
                HStack(spacing: 3) {
                    Circle()
                    Circle()
                    Circle()
                }
                .foregroundStyle(.tertiary)
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
