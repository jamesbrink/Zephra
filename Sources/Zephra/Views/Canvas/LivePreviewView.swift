import CoreGraphics
import SwiftUI
import ZephraCore
import ZephraStyle

/// The generation in flight, drawn as the frames it sends back.
///
/// What is on screen is a decode of the latent as it stood a moment ago, at most 256 pixels an
/// edge, scaled up to whatever room the canvas has. It is deliberately soft — `.medium`
/// interpolation rather than the `.high` a finished picture gets — because a frame is an
/// estimate and should not pretend to be the print.
///
/// The ground under it is the run's own shape, so the picture that lands at the end of the run
/// arrives in the rectangle its frames were already filling and nothing jumps. Before the first
/// frame that empty shape is all there is, which is the honest thing to show: the model has not
/// made anything yet.
///
/// The image is built once per frame and kept, rather than rebuilt inside `body`: `body` runs
/// on every progress update, and frames arrive far more rarely than those.
struct LivePreviewView: View {
    /// The newest frame, or nil before the first one lands.
    let preview: GenerationPreview?
    /// The size the run is making, which is the shape of the ground the frames sit on.
    let size: ImageSize

    @State private var frame: CGImage?

    var body: some View {
        Rectangle()
            .fill(Color.canvasBackground)
            .aspectRatio(size.aspectRatio, contentMode: .fit)
            .overlay {
                if let frame {
                    Image(decorative: frame, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipped()
            // The bytes are the frame's identity: a new decode is new bytes, and a run ending
            // puts them down. `initial` because the first frame may already be in hand when
            // this view appears, which is what happens on every frozen screenshot build.
            .onChange(of: preview?.pixels, initial: true) { _, _ in
                frame = preview?.makeImage()
            }
            .accessibilityLabel("The image being generated")
    }
}

#Preview("A frame in") {
    LivePreviewView(preview: PreviewImages.frame(), size: ImageSize(width: 1024, height: 1024))
        .padding(40)
        .frame(width: 520, height: 520)
        .background(Color.canvasBackground)
}

#Preview("Nothing yet") {
    LivePreviewView(preview: nil, size: ImageSize(width: 1024, height: 768))
        .padding(40)
        .frame(width: 520, height: 520)
        .background(Color.black)
}
