import AppKit
import SwiftUI
import ZephraCore
import ZephraStyle

/// One reference picture decoded off the main actor and drawn over its ground, re-read whenever
/// its `Request.key` moves. `ReferenceThumbnail` says which picture and which key; this view
/// holds the cache and the bitmap, so neither holds more than three stored properties.
struct ReferenceThumbnailImage: View {
    /// What a re-read is keyed on: the choice, the strip's revision, this slot, and how long the
    /// strip is, since taking a tile out moves every picture after it.
    struct Key: Hashable {
        let choice: Int
        let revision: Int
        let index: Int
        let pictures: Int
    }

    /// The picture to draw, nil for a slot past the strip's end, and the key it is read under.
    struct Request {
        let picture: ReferencePicture?
        let key: Key
    }

    let request: Request

    @Environment(ImageCache.self) private var cache
    @State private var bitmap: DrawnPicture?

    var body: some View {
        ground
            .overlay {
                if let bitmap {
                    Image(nsImage: bitmap.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipped()
            .task(id: request.key) {
                bitmap = nil
                guard let picture = request.picture, picture.hasPixels else { return }
                let made = await cache.referenceThumbnail(picture.data)
                guard !Task.isCancelled else { return }
                bitmap = made
            }
    }

    /// The checkerboard behind a reference that carries transparency, and otherwise the well's
    /// own fill. A transparent reference is one this Mac can now make, so the well has to be
    /// able to say so.
    @ViewBuilder
    private var ground: some View {
        if bitmap?.hasAlpha == true {
            TransparencyGround()
        } else {
            Rectangle().fill(.quaternary)
        }
    }
}
