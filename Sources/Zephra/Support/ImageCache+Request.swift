import Foundation
import ZephraCore

extension ImageCache {
    /// What a `SessionImage` is asking for: one image at one kind, and the shape to hold for
    /// it until the pixels arrive.
    ///
    /// The aspect is the request's rather than always the image's because the two places a
    /// thumbnail is drawn are square cells: a filmstrip tile that changed shape as its picture
    /// settled would make the grid twitch, and the full picture is letterboxed at its own.
    nonisolated struct Request: Sendable {
        /// The image to draw.
        let image: GeneratedImage
        /// Whole, or at the filmstrip's size.
        let kind: Kind
        /// Width over height of the placeholder, and of the frame the picture fills.
        let aspect: Double

        /// The whole picture, held at its own shape.
        static func full(_ image: GeneratedImage) -> Request {
            Request(image: image, kind: .full, aspect: image.settings.size.aspectRatio)
        }

        /// A filmstrip thumbnail, held square.
        static func thumbnail(_ image: GeneratedImage) -> Request {
            Request(image: image, kind: .thumbnail, aspect: 1)
        }

        /// The identity of the pixels asked for, which is what a view's task is keyed on:
        /// the image and the kind, and not the bytes, which a request never has to compare.
        var key: Key { Key(id: image.id, kind: kind) }

        /// One image at one kind.
        nonisolated struct Key: Hashable, Sendable {
            let id: UUID
            let kind: Kind
        }
    }
}
