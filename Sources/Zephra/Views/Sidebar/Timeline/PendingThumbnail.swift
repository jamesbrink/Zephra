import SwiftUI

/// The place a seed will take once it has been rendered: a dashed square that fills the same
/// cell the picture will, so a run's grid is laid out once and then filled in.
///
/// The three dots do not animate, and none of them is amber. Amber means the model is working
/// on that thing, and nothing is happening in this square: the one being worked on is the card
/// above the grid, whose step segments are the real measurement.
struct PendingThumbnail: View {
    var body: some View {
        RoundedRectangle(cornerRadius: ZephraChrome.tileRadius, style: .continuous)
            .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .aspectRatio(1, contentMode: .fit)
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
    .frame(width: 200)
    .padding()
    .background(Color.canvasBackground)
}
