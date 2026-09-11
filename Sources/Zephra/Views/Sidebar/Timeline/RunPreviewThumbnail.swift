import CoreGraphics
import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraStyle

/// The newest frame of the run in flight, at the size of a square on the wall below it.
///
/// It is on the running card so that progress is visible while you are looking at something
/// else: the step segments say how far along the model is, and this says what it is making.
/// Amber under it until the first frame lands, so the empty square reads as part of the card
/// rather than as a picture that failed to load.
///
/// It builds and keeps its own image rather than sharing the canvas's: the two are separate
/// views of the same bytes, and a `CGImage` over a `Data` is a header, not a copy.
struct RunPreviewThumbnail: View {
    @Environment(GenerationStore.self) private var store
    @State private var frame: CGImage?

    /// The square's edge: the height of two lines of the card beside it.
    static let edge: CGFloat = 36

    var body: some View {
        shape
            .fill(ZephraChrome.safelightTint)
            .frame(width: Self.edge, height: Self.edge)
            .overlay {
                if let frame {
                    Image(decorative: frame, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipShape(shape)
            .onChange(of: store.livePreview?.pixels, initial: true) { _, _ in
                frame = store.livePreview?.makeImage()
            }
            // The card around it already says a generation is running, and reads it out.
            .accessibilityHidden(true)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ZephraChrome.tileRadius, style: .continuous)
    }
}

#Preview("With and without a frame") {
    HStack(spacing: 8) {
        RunPreviewThumbnail()
            .environment(GenerationStore.preview(state: .ready, livePreview: PreviewImages.frame()))
        RunPreviewThumbnail()
            .environment(GenerationStore.preview(state: .ready))
    }
    .padding()
    .background(Color.canvasBackground)
}
