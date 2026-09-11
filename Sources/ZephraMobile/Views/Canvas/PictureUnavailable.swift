import SwiftUI
import ZephraStyle

/// The rectangle where a picture would be, while it is coming or once it is clear that it is
/// not.
///
/// The waiting half is quiet on purpose: a fetch off a Mac on the same network is a moment,
/// and a spinner for a moment is a flicker. The other half says the plain thing, because a
/// blank square where a picture should be reads as a bug rather than as a link that is down.
struct PictureUnavailable: View {
    /// Whether the bytes are still on their way; false once they are not coming.
    let isFetching: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: ZephraChrome.cardRadius, style: .continuous)
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if !isFetching {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("This picture is on your Mac.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(24)
                }
            }
    }
}

#Preview("Not coming") {
    PictureUnavailable(isFetching: false)
        .padding(40)
        .background(Color.canvasBackground)
}
