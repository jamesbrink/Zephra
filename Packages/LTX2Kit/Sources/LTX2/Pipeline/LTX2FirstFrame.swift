import CoreGraphics
import Foundation

/// A picture to hold as the clip's first frame, and how strongly to hold it.
public struct LTX2FirstFrame: Sendable {
    /// The picture. Scaling and cropping it to the clip's size is the pipeline's job.
    public var image: CGImage
    /// The conditioning strength, from 0 (the picture changes nothing, which is text-to-video)
    /// to 1 (the first frame is the picture and stays it).
    ///
    /// This runs the opposite way from the interface's reference strength, which everywhere in
    /// Zephra reads as "how much of the picture to throw away". `LTX2RequestMapper` is where the
    /// two meet.
    public var strength: Float

    public init(image: CGImage, strength: Float) {
        self.image = image
        self.strength = strength
    }
}
