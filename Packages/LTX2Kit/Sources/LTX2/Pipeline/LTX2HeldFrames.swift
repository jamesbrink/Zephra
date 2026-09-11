import CoreGraphics
import Foundation

/// Pictures to hold at the head of the clip, and how strongly to hold them.
///
/// One picture is image-to-video: it becomes the clip's first frame. A run of `1 + 8k`
/// pictures is a clip carried on from the end of another: they are the earlier clip's last
/// frames, encoded together to `k + 1` latent frames and held at the head so the motion runs
/// on across the join. The reference's `pipeline_ltx2_condition.py` writes a multi-frame
/// condition at latent index 0 exactly this way.
public struct LTX2HeldFrames: Sendable {
    /// The pictures, oldest first. Scaling and cropping them to the clip's size is the
    /// pipeline's job; the count must be on the autoencoder's ladder, `1 + 8k`.
    public var images: [CGImage]
    /// The conditioning strength, from 0 (the pictures change nothing, which is text-to-video)
    /// to 1 (the frames are the pictures and stay them).
    ///
    /// This runs the opposite way from the interface's reference strength, which everywhere in
    /// Zephra reads as "how much of the picture to throw away". `LTX2RequestMapper` is where the
    /// two meet.
    public var strength: Float

    public init(images: [CGImage], strength: Float) {
        self.images = images
        self.strength = strength
    }

    /// One picture as the first frame.
    public init(image: CGImage, strength: Float) {
        self.init(images: [image], strength: strength)
    }
}
