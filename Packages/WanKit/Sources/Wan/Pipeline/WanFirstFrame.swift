import CoreGraphics
import Foundation

/// A picture to hold as the clip's first frame.
///
/// Held exactly, with no strength: the model reads the picture's latent as its first frame at
/// timestep zero on every step and generates the rest of the clip around it, which is what
/// image-to-video means for this family. A strength would be a different mechanism, not a
/// number on this one.
public struct WanFirstFrame: Sendable {
    /// The picture. Scaling and cropping it to the clip's size is the pipeline's job.
    public var image: CGImage

    public init(image: CGImage) {
        self.image = image
    }
}
