import SwiftUI
import UIKit

/// The picture in the well, decoded off the main actor.
///
/// The bytes are what the draft holds and what will cross the link, so this decodes them
/// rather than keeping a second copy of the picture: one truth, drawn.
struct ReferenceThumbnail: View {
    /// The picture as PNG.
    let data: Data
    @State private var picture: UIImage?

    var body: some View {
        Color.clear
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
}
