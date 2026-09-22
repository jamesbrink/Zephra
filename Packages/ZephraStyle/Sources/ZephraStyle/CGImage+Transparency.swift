import CoreGraphics

/// Whether a decoded picture can carry transparency, which is the one question
/// `TransparencyGround` is drawn from wherever the pixels are already in hand.
///
/// Here rather than in either app because both ask it and both must answer the same way: the
/// Mac's caches ask it of what they decoded, and the phone asks it of a `UIImage`'s own
/// `cgImage`. Where there is no decoded picture to ask — a library cell that has not fetched
/// its thumbnail, a file the inspector only knows by name — the answer comes from the file's
/// header instead, through `PNGHeader.hasAlpha`.
///
/// "Can carry" rather than "does": a fully opaque RGBA picture answers yes, and the ground
/// behind it is covered by its own pixels. Reading every fourth byte to be sure would be a
/// pass over the whole bitmap to decide the colour of something nobody will see.
extension CGImage {
    /// True when the bitmap has an alpha channel at all.
    public var hasTransparency: Bool {
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            true
        case .none, .noneSkipFirst, .noneSkipLast:
            false
        @unknown default:
            false
        }
    }
}
