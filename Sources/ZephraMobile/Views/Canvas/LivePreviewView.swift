import SwiftUI
import UIKit
import ZephraLinkProtocol
import ZephraStyle

/// The generation in flight, drawn as the frames the Mac sends back.
///
/// What is on screen is a decode of the latent as it stood a moment ago, at most 256 pixels an
/// edge and JPEG on the wire, scaled up to whatever room the phone has. Deliberately soft —
/// `.medium` interpolation rather than the `.high` a finished picture gets — because a frame is
/// an estimate and should not pretend to be the print. The Mac's view of the same name says the
/// same thing about its own frames.
///
/// The ground under it is the run's own shape, so the picture that lands at the end arrives in
/// the rectangle its frames were already filling.
struct LivePreviewView: View {
    /// The newest frame.
    let frame: PreviewFrameDTO
    /// The shape of the run, which is the shape of the ground the frames sit on.
    let aspect: Double

    @State private var picture: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color.canvasBackground)
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                if let picture {
                    Image(uiImage: picture)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: ZephraChrome.cardRadius, style: .continuous))
            // The bytes are the frame's identity: a new decode is new bytes. Off the main
            // actor, since frames arrive several times a second while the model works.
            .task(id: frame.jpeg) { picture = await DecodedPicture.from(frame.jpeg) }
            .accessibilityLabel("The image being generated")
    }
}
