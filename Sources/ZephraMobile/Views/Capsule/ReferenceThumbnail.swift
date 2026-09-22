import SwiftUI
import UIKit
import ZephraStyle

/// The picture in the well, decoded off the main actor.
///
/// The bytes are what the draft holds and what will cross the link, so this decodes them
/// rather than keeping a second copy of the picture: one truth, drawn.
struct ReferenceThumbnail: View {
    /// The picture as PNG.
    let data: Data
    @State private var picture: UIImage?

    var body: some View {
        ground
            .overlay {
                if let picture {
                    Image(uiImage: picture)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipped()
            .task(id: data) { picture = await DecodedPicture.from(data) }
            .accessibilityLabel("The picture this run starts from")
    }

    /// The checkerboard behind a picture that carries transparency, and nothing behind one
    /// that does not, which is what the well has always drawn.
    @ViewBuilder
    private var ground: some View {
        if picture?.cgImage?.hasTransparency == true {
            TransparencyGround()
        } else {
            Color.clear
        }
    }
}
