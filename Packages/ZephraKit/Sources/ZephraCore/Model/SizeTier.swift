/// How a size compares in cost with the model's default, for grouping the offered sizes so a
/// person who has never chosen one can see which are quick and which are slow.
///
/// Pixels are the proxy: a generation's time grows with the token count, which grows with the
/// pixel count, and a clip's with that times its frames. Three tiers rather than a number,
/// since "about twice as long" is what a person can act on and "1.7×" is not.
public enum SizeTier: CaseIterable, Hashable, Sendable {
    /// Well under the default's pixel count: quicker, with less detail.
    case faster
    /// Near the default.
    case standard
    /// Well over the default: more detail, and slower to match.
    case larger

    /// The section heading for sizes in this tier.
    public var title: String {
        switch self {
        case .faster: "Faster"
        case .standard: "Standard"
        case .larger: "Larger, slower"
        }
    }
}

extension ModelCapabilities {
    /// Which tier `size` falls in against this model's default: under three quarters of its
    /// pixels is faster, over one and a half times is larger, and the rest is standard.
    public func tier(of size: ImageSize) -> SizeTier {
        let ratio = Double(size.pixelCount) / Double(max(defaultSize.pixelCount, 1))
        if ratio < 0.75 { return .faster }
        if ratio > 1.5 { return .larger }
        return .standard
    }
}
